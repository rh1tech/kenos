import AppKit

/// Retitles AppKit’s own menu bar entries (File / Edit / View / Window / Help,
/// and leftover Close / Close All) so they follow Settings › Language.
/// `AppleLanguages` alone is not enough when the main app bundle has no
/// `.lproj` folders — AppKit keeps the English titles.
enum MenuChrome {
    /// English key for each top-level title we may see (English or already Russian).
    private static let tops: [String: String] = [
        "File": "File", "Файл": "File",
        "Edit": "Edit", "Правка": "Edit",
        "View": "View", "Вид": "View",
        "Window": "Window", "Окно": "Window",
        "Help": "Help", "Справка": "Help",
    ]

    private static let items: [String: String] = [
        "Close": "Close", "Закрыть": "Close",
        "Close All": "Close All", "Закрыть все": "Close All",
        "Close Window": "Close Window", "Закрыть окно": "Close Window",
        "Close All Windows": "Close All Windows", "Закрыть все окна": "Close All Windows",
    ]

    static func retitle() {
        guard let menu = NSApp.mainMenu else { return }
        for item in menu.items {
            if let key = tops[item.title] {
                item.title = L10n.tr(key)
            }
            if let submenu = item.submenu {
                walk(submenu)
            }
        }
    }

    private static func walk(_ menu: NSMenu) {
        for item in menu.items {
            if let key = items[item.title] {
                item.title = L10n.tr(key)
            }
            if let submenu = item.submenu {
                walk(submenu)
            }
        }
    }
}
