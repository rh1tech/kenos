import Foundation

// Fetches uBlock Origin's default filter lists, converts what WebKit can
// express into a content-blocker JSON file under Application Support, and
// asks Shield to recompile. Same sources as gorhill/uBlock's assets.json.

@MainActor
final class FilterLists: ObservableObject {
    static let shared = FilterLists()

    /// uBlock CDN (and EasyList via uAssetsCDN) — same defaults as stock uBlock.
    static let sources: [(id: String, url: String)] = [
        ("easylist", "https://ublockorigin.github.io/uAssetsCDN/thirdparties/easylist.txt"),
        ("easyprivacy", "https://ublockorigin.github.io/uAssetsCDN/thirdparties/easyprivacy.txt"),
        ("ublock-filters", "https://ublockorigin.github.io/uAssetsCDN/filters/filters.min.txt"),
        ("ublock-badware", "https://ublockorigin.github.io/uAssetsCDN/filters/badware.min.txt"),
        ("ublock-privacy", "https://ublockorigin.github.io/uAssetsCDN/filters/privacy.min.txt"),
        ("ublock-quick-fixes", "https://ublockorigin.github.io/uAssetsCDN/filters/quick-fixes.min.txt"),
        ("ublock-unbreak", "https://ublockorigin.github.io/uAssetsCDN/filters/unbreak.min.txt"),
    ]

    static let maxRules = 45_000

    @Published private(set) var updating = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var lastRuleCount = 0

    private let checkedKey = "shield.lists.checked"
    private let updatedKey = "shield.lists.updated"
    /// Hours between automatic refreshes. Prefs can override.
    var intervalHours: Double {
        get {
            let v = Store.settings.object(forKey: "shield.lists.intervalHours") as? Double
            return v ?? 24
        }
        set { Store.settings.set(newValue, forKey: "shield.lists.intervalHours") }
    }

    private init() {
        if let t = Store.settings.object(forKey: updatedKey) as? Date {
            lastUpdated = t
        }
        if let meta = try? Data(contentsOf: Shield.supportMeta),
           let obj = try? JSONSerialization.jsonObject(with: meta) as? [String: Any],
           let n = obj["total"] as? Int {
            lastRuleCount = n
        }
    }

    /// Once a day (or whatever intervalHours says), quietly. Interval 0 = manual only.
    func checkIfDue() {
        guard intervalHours > 0 else { return }
        let last = Store.settings.object(forKey: checkedKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) >= intervalHours * 3600 else { return }
        Task { await refresh(force: false) }
    }

    func refresh(force: Bool = true) async {
        guard !updating else { return }
        updating = true
        lastError = nil
        defer { updating = false }

        Store.settings.set(Date(), forKey: checkedKey)

        var blocks: [[String: Any]] = []
        var cosmetics: [[String: Any]] = []
        var exceptions: [[String: Any]] = []
        var perList: [String: Int] = [:]

        let priority = Self.bundledHostRules()
        perList["hosts"] = priority.count

        for source in Self.sources {
            do {
                let text = try await fetch(source.url)
                var n = 0
                for line in text.split(whereSeparator: \.isNewline) {
                    for rule in FilterConverter.rules(from: String(line)) {
                        let type = (rule["action"] as? [String: Any])?["type"] as? String
                        switch type {
                        case "block": blocks.append(rule)
                        case "css-display-none": cosmetics.append(rule)
                        case "ignore-previous-rules": exceptions.append(rule)
                        default: break
                        }
                        n += 1
                    }
                }
                perList[source.id] = n
            } catch {
                lastError = "\(source.id): \(error.localizedDescription)"
                // Keep going — partial update still beats nothing.
            }
        }

        blocks = Self.dedupe(blocks)
        cosmetics = Self.dedupe(cosmetics)
        exceptions = Self.dedupe(exceptions)
        let hosts = Self.dedupe(priority)

        let domainBlocks = blocks.filter { Self.isDomainBlock($0) }
        let otherBlocks = blocks.filter { !Self.isDomainBlock($0) }

        var take: [[String: Any]] = []
        for group in [hosts, domainBlocks, otherBlocks] {
            let room = Self.maxRules - take.count
            if room <= 0 { break }
            take.append(contentsOf: group.prefix(room))
        }
        take = Self.dedupe(take)
        var budget = Self.maxRules - take.count
        let takeCosmo = Array(cosmetics.prefix(Int(Double(max(0, budget)) * 0.7)))
        budget -= takeCosmo.count
        let takeEx = Array(exceptions.prefix(budget))
        let rules = take + takeCosmo + takeEx

        guard !rules.isEmpty else {
            if lastError == nil { lastError = "No rules downloaded" }
            return
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: rules)
            try data.write(to: Shield.supportJSON, options: .atomic)
            let stamp = ISO8601DateFormatter().string(from: Date())
            let meta: [String: Any] = [
                "source": "gorhill/uBlock + hosts",
                "updated": stamp,
                "lists": perList,
                "hosts": hosts.count,
                "blocks": take.count,
                "cosmetics": takeCosmo.count,
                "exceptions": takeEx.count,
                "total": rules.count,
            ]
            let metaData = try JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys])
            try metaData.write(to: Shield.supportMeta, options: .atomic)
            lastUpdated = Date()
            lastRuleCount = rules.count
            Store.settings.set(lastUpdated, forKey: updatedKey)
            Shield.shared.compile()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// d3ward / known tracker hosts shipped with the app — always first in the list.
    private static func bundledHostRules() -> [[String: Any]] {
        var rules: [[String: Any]] = []
        var seen = Set<String>()
        for name in ["d3host", "hosts"] {
            guard let url = bundledTextURL(name),
                  let text = try? String(contentsOf: url, encoding: .utf8)
            else { continue }
            for raw in text.split(whereSeparator: \.isNewline) {
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.isEmpty || line.hasPrefix("#") { continue }
                let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
                guard let first = parts.first else { continue }
                let host: String
                if ["0.0.0.0", "127.0.0.1", "::1"].contains(first), parts.count >= 2 {
                    host = parts[1]
                } else {
                    host = first
                }
                let h = host.trimmingCharacters(in: CharacterSet(charactersIn: "*."))
                    .trimmingCharacters(in: .whitespaces)
                    .lowercased()
                guard !h.isEmpty, !seen.contains(h), !h.contains("/"),
                      h.range(of: #"^[a-z0-9.-]+\.[a-z]{2,}$"#, options: .regularExpression) != nil
                else { continue }
                seen.insert(h)
                let uf = "^https?://([^/]+\\.)?\(NSRegularExpression.escapedPattern(for: h))"
                guard !uf.contains("|") else { continue }
                rules.append(["trigger": ["url-filter": uf], "action": ["type": "block"]])
            }
        }
        return rules
    }

    private static func bundledTextURL(_ name: String) -> URL? {
        if let resource = Bundle.main.resourceURL {
            let bundled = resource.appendingPathComponent("Kenos_Kenos.bundle")
            if let b = Bundle(url: bundled) {
                if let u = b.url(forResource: name, withExtension: "txt", subdirectory: "Shield") { return u }
                if let u = b.url(forResource: name, withExtension: "txt") { return u }
            }
            let flat = bundled.appendingPathComponent("Contents/Resources/Shield/\(name).txt")
            if FileManager.default.fileExists(atPath: flat.path) { return flat }
            let res = resource.appendingPathComponent("Shield/\(name).txt")
            if FileManager.default.fileExists(atPath: res.path) { return res }
        }
        return Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Shield")
            ?? Bundle.module.url(forResource: name, withExtension: "txt")
    }

    private static func isDomainBlock(_ rule: [String: Any]) -> Bool {
        guard let trigger = rule["trigger"] as? [String: Any],
              let uf = trigger["url-filter"] as? String,
              uf.hasPrefix("^https?://")
        else { return false }
        return trigger["resource-type"] == nil
    }

    private func fetch(_ urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("KenosBrowser/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 60
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        return text
    }

    private static func dedupe(_ rules: [[String: Any]]) -> [[String: Any]] {
        var seen = Set<String>()
        var out: [[String: Any]] = []
        out.reserveCapacity(rules.count)
        for r in rules {
            guard let data = try? JSONSerialization.data(withJSONObject: r, options: [.sortedKeys]),
                  let key = String(data: data, encoding: .utf8)
            else { continue }
            if seen.insert(key).inserted { out.append(r) }
        }
        return out
    }
}

// MARK: - Adblock → WKContentRuleList

enum FilterConverter {
    private static let resourceMap: [String: String] = [
        "script": "script", "image": "image", "stylesheet": "style-sheet",
        "object": "media", "xmlhttprequest": "raw", "xhr": "raw",
        "media": "media", "font": "font", "subdocument": "document",
        "other": "other", "websocket": "websocket", "ping": "raw", "fetch": "fetch",
    ]

    static func rules(from line: String) -> [[String: Any]] {
        let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty || line.hasPrefix("!") || line.hasPrefix("[") { return [] }
        if line.contains("+js(") || line.contains(":has(") || line.contains(":xpath(") || line.contains("##^") {
            return []
        }
        if line.contains("#@#") || line.contains("#?#") || line.contains("#$#") {
            return []
        }

        if line.hasPrefix("@@") {
            var body = String(line.dropFirst(2))
            var opts = Options()
            if let dollar = body.firstIndex(of: "$") {
                opts = Options(String(body[body.index(after: dollar)...]))
                body = String(body[..<dollar])
            }
            guard let uf = urlFilter(body), let trig = trigger(uf, opts) else { return [] }
            return [["trigger": trig, "action": ["type": "ignore-previous-rules"]]]
        }

        if let range = line.range(of: "##"), !line.hasPrefix("@@") {
            if line.contains("#@#") { return [] }
            let left = String(line[..<range.lowerBound])
            let sel = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if sel.isEmpty || sel.hasPrefix("+js") || sel.contains(":style(") || sel.count > 512 { return [] }
            for bad in [":not(", ":has(", ":is(", ":where(", ":nth-", "::"] {
                if sel.contains(bad) { return [] }
            }
            var trigger: [String: Any] = ["url-filter": ".*"]
            if !left.isEmpty {
                let domains = left.split(separator: ",").map(String.init)
                    .filter { !$0.hasPrefix("~") }
                    .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "*.")) }
                    .filter { !$0.isEmpty }
                guard !domains.isEmpty else { return [] }
                trigger["if-domain"] = domains.prefix(40).map { "*\($0)" }
            }
            return [["trigger": trigger, "action": ["type": "css-display-none", "selector": sel]]]
        }

        var body = line
        var opts = Options()
        if let dollar = line.firstIndex(of: "$") {
            let opt = String(line[line.index(after: dollar)...])
            opts = Options(opt)
            body = String(line[..<dollar])
            let parts = Set(opt.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
            let bad: Set<String> = ["popup", "csp", "inline-script", "inline-font", "webrtc"]
            if !parts.isDisjoint(with: bad), parts.isDisjoint(with: Set(resourceMap.keys)) {
                return []
            }
        }
        guard let uf = urlFilter(body), let trig = trigger(uf, opts) else { return [] }
        return [["trigger": trig, "action": ["type": "block"]]]
    }

    private struct Options {
        var third: Bool? = nil
        var resources: [String] = []
        var domains: [String] = []
        var unless: [String] = []

        init() {}

        init(_ opt: String) {
            for part in opt.split(separator: ",") {
                let p = part.trimmingCharacters(in: .whitespaces).lowercased()
                if p == "third-party" || p == "3p" { third = true }
                else if p == "~third-party" || p == "first-party" || p == "1p" { third = false }
                else if let mapped = FilterConverter.resourceMap[p] {
                    if !resources.contains(mapped) { resources.append(mapped) }
                } else if p.hasPrefix("domain=") {
                    for d in p.dropFirst(7).split(separator: "|") {
                        let s = String(d).trimmingCharacters(in: .whitespaces)
                        if s.hasPrefix("~") {
                            unless.append(String(s.dropFirst()).trimmingCharacters(in: CharacterSet(charactersIn: "*.")))
                        } else if !s.isEmpty {
                            domains.append(s.trimmingCharacters(in: CharacterSet(charactersIn: "*.")))
                        }
                    }
                }
            }
        }
    }

    private static func trigger(_ urlFilter: String, _ opts: Options) -> [String: Any]? {
        // WebKit rejects regex disjunctions (`|`) in url-filter.
        guard !urlFilter.isEmpty, !urlFilter.contains("|") else { return nil }
        var t: [String: Any] = ["url-filter": urlFilter]
        if opts.third == true { t["load-type"] = ["third-party"] }
        if opts.third == false { t["load-type"] = ["first-party"] }
        if !opts.resources.isEmpty {
            let mapped = opts.resources.map { $0 == "websocket" ? "other" : $0 }
            var seen: [String] = []
            for r in mapped where !seen.contains(r) { seen.append(r) }
            t["resource-type"] = seen
        }
        // Only one of if-domain / unless-domain is allowed.
        if !opts.domains.isEmpty && opts.unless.isEmpty {
            t["if-domain"] = opts.domains.prefix(50).map { "*\($0)" }
        } else if !opts.unless.isEmpty {
            t["unless-domain"] = opts.unless.prefix(50).map { "*\($0)" }
        }
        return t
    }

    private static func urlFilter(_ pattern: String) -> String? {
        var p = pattern.trimmingCharacters(in: .whitespaces)
        if p.isEmpty { return nil }
        if p.hasPrefix("/") && p.hasSuffix("/") && p.count > 2 { return nil }

        // Adblock trailing `|` = end anchor, not a regex pipe.
        var endAnchor = false
        if p.hasSuffix("|"), !p.hasSuffix("||") {
            endAnchor = true
            p = String(p.dropLast())
        }

        if p.hasPrefix("||") {
            let rest = String(p.dropFirst(2))
            var host = ""
            var path = ""
            var sep: Character?
            for (i, ch) in rest.enumerated() {
                if ch == "^" || ch == "/" {
                    host = String(rest.prefix(i))
                    sep = ch
                    path = String(rest.dropFirst(i + 1))
                    break
                }
            }
            if sep == nil {
                if rest.range(of: #"^[a-z0-9.-]+$"#, options: .regularExpression) != nil {
                    return domainFilter(rest)
                }
                return nil
            }
            if sep == "^" && path.isEmpty { return domainFilter(host) }
            path = path.trimmingCharacters(in: CharacterSet(charactersIn: "^"))
            guard let pathRe = wildcardRegex(path, endAnchor: endAnchor) else { return nil }
            let uf = "^https?://([^/]+\\.)?\(NSRegularExpression.escapedPattern(for: host))/.*\(pathRe)"
            return uf.contains("|") ? nil : uf
        }

        if p.hasPrefix("|http") {
            var body = String(p.dropFirst())
            if body.hasSuffix("|") {
                body = String(body.dropLast())
                endAnchor = true
            }
            guard let re = wildcardRegex(body, endAnchor: endAnchor) else { return nil }
            return "^" + re
        }

        if p.contains("/") || p.contains("*") || p.contains(".") {
            return wildcardRegex(p, endAnchor: endAnchor)
        }
        return nil
    }

    private static func domainFilter(_ host: String) -> String {
        let h = host.trimmingCharacters(in: CharacterSet(charactersIn: "*."))
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        // No `([:/?]|$)` — WebKit forbids `|` in url-filter.
        return "^https?://([^/]+\\.)?\(NSRegularExpression.escapedPattern(for: h))"
    }

    private static func wildcardRegex(_ s: String, endAnchor: Bool = false) -> String? {
        var out = ""
        for ch in s {
            if ch == "*" { out += ".*" }
            else { out += NSRegularExpression.escapedPattern(for: String(ch)) }
        }
        if endAnchor { out += "$" }
        if out.contains("|") { return nil }
        return out
    }
}
