import Foundation
import SwiftUI
import AppKit

/// In-app language. System follows the Mac; English and Russian are fixed.
enum Tongue: String, CaseIterable, Identifiable {
    case system, en, ru

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return L10n.tr("lang.system")
        case .en: return "English"
        case .ru: return "Русский"
        }
    }

    /// BCP-47 tag used to pick a `.lproj`, or nil to follow the Mac.
    var tag: String? {
        switch self {
        case .system: return nil
        case .en: return "en"
        case .ru: return "ru"
        }
    }
}

/// Looks up strings in Kenos's own bundle, honouring the language chosen in Settings.
enum L10n {
    /// Written from Preferences on the main actor; read from any context.
    nonisolated(unsafe) static var tongueTag: String?

    /// The bundle for the active language (en / ru / system).
    static var bundle: Bundle {
        let tag = tongueTag ?? Locale.current.language.languageCode?.identifier
        if let tag,
           let path = Bundle.module.path(forResource: tag, ofType: "lproj"),
           let b = Bundle(path: path) {
            return b
        }
        if let path = Bundle.module.path(forResource: "en", ofType: "lproj"),
           let b = Bundle(path: path) {
            return b
        }
        return .module
    }

    static func tr(_ key: String) -> String {
        NSLocalizedString(key, tableName: "Localizable", bundle: bundle, value: key, comment: "")
    }

    static func tr(_ key: String, _ args: CVarArg...) -> String {
        let locale = Locale(identifier: tongueTag ?? Locale.current.identifier)
        return String(format: tr(key), locale: locale, arguments: args)
    }

    /// Read the saved language and push it into `AppleLanguages` before AppKit
    /// builds File / Edit / View / Window / Help — those titles follow the
    /// process language, not `Bundle.module`.
    static func bootstrap() {
        let tongue = Store.settings.string(forKey: "tongue").flatMap(Tongue.init) ?? .system
        tongueTag = tongue.tag
        applyAppleLanguages(tongue.tag)
    }

    /// Point the process at `en` / `ru`, or clear the override for System.
    static func applyAppleLanguages(_ tag: String?) {
        if let tag {
            UserDefaults.standard.set([tag], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
    }

    /// Menu bar titles only pick up a new language after a clean start.
    static func relaunchForLanguage() {
        guard !Store.testing else { return }
        let url = Bundle.main.bundleURL
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", url.path]
        try? task.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSApp.terminate(nil)
        }
    }
}

/// Marks a view as depending on the chosen language so labels refresh when it changes.
private struct TongueRefresh: ViewModifier {
    @ObservedObject private var prefs = Preferences.shared
    func body(content: Content) -> some View {
        content.id(prefs.tongue)
    }
}

extension View {
    /// Re-render when Settings › Language changes.
    func localized() -> some View { modifier(TongueRefresh()) }
}
