import Foundation
import WebKit

// Ad blocking via WKContentRuleList, fed by uBlock Origin's public filter
// lists (EasyList, EasyPrivacy, uBlock filters, …). WebKit cannot run
// uBlock's engine; we translate what content blockers can express.
//
// Resolution order for the JSON rule file:
//   1. ~/Library/Application Support/Kenos/Shield/ublock.json  (updated in-app)
//   2. Bundled baseline shipped with the app
//
// FilterLists refreshes (1) from uBlock's CDN on a schedule, then asks Shield
// to recompile.

@MainActor
final class Shield: ObservableObject {
    static let shared = Shield()

    private var storeID = "kenos-shield-idle"
    private(set) var list: WKContentRuleList?
    private var waiting: [WKUserContentController] = []

    @Published private(set) var trouble: String?
    /// Rules in the active compiled list.
    @Published private(set) var ruleCount = 0
    @Published private(set) var listSource = "—"

    var enabled = true

    private(set) var paused: Set<String> = Set(
        Store.settings.stringArray(forKey: "shield.paused") ?? []
    )

    func isPaused(on host: String?) -> Bool {
        guard let host else { return false }
        return paused.contains(host)
    }

    func pause(_ host: String, _ off: Bool) {
        if off { paused.insert(host) } else { paused.remove(host) }
        Store.settings.set(Array(paused).sorted(), forKey: "shield.paused")
    }

    func tune(_ controller: WKUserContentController, for host: String?) {
        guard let list else { return }
        controller.remove(list)
        if enabled, !isPaused(on: host) { controller.add(list) }
    }

    func protect(_ controller: WKUserContentController) {
        if let list {
            if enabled { controller.add(list) }
        } else {
            waiting.append(controller)
        }
    }

    func apply(to controllers: [WKUserContentController]) {
        guard let list else { return }
        for controller in controllers {
            controller.remove(list)
            if enabled { controller.add(list) }
        }
    }

    /// Load JSON from disk / bundle and compile. Safe to call again after an update.
    func compile() {
        trouble = nil
        guard let payload = Self.loadJSON() else {
            trouble = "No block list found"
            listSource = "missing"
            return
        }
        ruleCount = payload.ruleCount
        listSource = payload.label
        storeID = "kenos-shield-" + payload.digest.prefix(12)

        guard let store = WKContentRuleListStore.default() else {
            trouble = "WebKit has nowhere to compile it"
            return
        }

        let json = payload.json
        let id = storeID
        store.removeContentRuleList(forIdentifier: id) { _ in
            store.compileContentRuleList(
                forIdentifier: id,
                encodedContentRuleList: json
            ) { [weak self] compiled, error in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    guard let compiled else {
                        self.trouble = error?.localizedDescription
                            ?? "Compiling the block list failed"
                        return
                    }
                    // Swap: remove old list from waiting controllers, add new.
                    if let old = self.list {
                        for c in self.waiting { c.remove(old) }
                    }
                    self.list = compiled
                    self.trouble = nil
                    if self.enabled { self.waiting.forEach { $0.add(compiled) } }
                    NotificationCenter.default.post(name: .kenosShieldCompiled, object: nil)
                }
            }
        }
    }

    // MARK: - JSON location

    struct Payload {
        let json: String
        let ruleCount: Int
        let label: String
        let digest: String
    }

    /// Updated lists live here; the updater writes `ublock.json` + `meta.json`.
    static var supportFolder: URL {
        let url = Store.file("Shield")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var supportJSON: URL { supportFolder.appendingPathComponent("ublock.json") }
    static var supportMeta: URL { supportFolder.appendingPathComponent("meta.json") }

    static func loadJSON() -> Payload? {
        if let data = try? Data(contentsOf: supportJSON),
           let json = String(data: data, encoding: .utf8),
           json.first == "[" {
            let count = ruleCount(in: data)
            let digest = sha256(data)
            var label = "updated"
            if let meta = try? Data(contentsOf: supportMeta),
               let obj = try? JSONSerialization.jsonObject(with: meta) as? [String: Any],
               let when = obj["updated"] as? String {
                label = "updated \(when)"
            }
            return Payload(json: json, ruleCount: count, label: label, digest: digest)
        }
        if let url = bundledJSONURL(),
           let data = try? Data(contentsOf: url),
           let json = String(data: data, encoding: .utf8) {
            return Payload(
                json: json,
                ruleCount: ruleCount(in: data),
                label: "bundled",
                digest: sha256(data)
            )
        }
        return nil
    }

    private static func bundledJSONURL() -> URL? {
        if let resource = Bundle.main.resourceURL {
            let bundled = resource.appendingPathComponent("Kenos_Kenos.bundle")
            if let b = Bundle(url: bundled) {
                if let u = b.url(forResource: "ublock", withExtension: "json", subdirectory: "Shield") { return u }
                if let u = b.url(forResource: "ublock", withExtension: "json") { return u }
            }
            let flat = bundled.appendingPathComponent("Contents/Resources/Shield/ublock.json")
            if FileManager.default.fileExists(atPath: flat.path) { return flat }
            let res = resource.appendingPathComponent("Shield/ublock.json")
            if FileManager.default.fileExists(atPath: res.path) { return res }
        }
        let beside = URL(fileURLWithPath: CommandLine.arguments[0])
            .deletingLastPathComponent()
            .appendingPathComponent("Kenos_Kenos.bundle")
        if let b = Bundle(url: beside) {
            return b.url(forResource: "ublock", withExtension: "json", subdirectory: "Shield")
                ?? b.url(forResource: "ublock", withExtension: "json")
        }
        return nil
    }

    private static func ruleCount(in data: Data) -> Int {
        // Cheap: count top-level objects via `"action"` keys.
        data.withUnsafeBytes { raw -> Int in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            let needle = Array("\"action\"".utf8)
            var count = 0
            var i = 0
            let n = raw.count
            while i + needle.count <= n {
                var ok = true
                for j in 0..<needle.count {
                    if base[i + j] != needle[j] { ok = false; break }
                }
                if ok { count += 1; i += needle.count } else { i += 1 }
            }
            return count
        }
    }

    private static func sha256(_ data: Data) -> String {
        // Avoid CryptoKit import churn in every file — use a short FNV-ish digest.
        var hash: UInt64 = 14695981039346656037
        for b in data {
            hash ^= UInt64(b)
            hash &*= 1099511628211
        }
        return String(format: "%016llx", hash)
    }
}

extension Notification.Name {
    static let kenosShieldCompiled = Notification.Name("kenosShieldCompiled")
    /// Trouble › Edit address — put the failed URL back in the field and focus it.
    static let kenosEditFailedAddress = Notification.Name("kenosEditFailedAddress")
}
