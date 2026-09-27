import SwiftUI
import AppKit

/// Preferences for Kenos. Categories across the top; one pane below —
/// not a left-rail list of pages. Same switches as before, grouped for
/// how people actually look for them.
struct SettingsPanel: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences

    @ObservedObject private var updater = Updater.shared
    @ObservedObject private var shield = Shield.shared
    @ObservedObject private var filters = FilterLists.shared
    @State private var isDefault = Links.isDefault
    @State private var page: Page = Page(rawValue: Store.settings.string(forKey: "settings.page") ?? "") ?? .general

    private var filterDetail: String {
        if prefs.shieldListHours == 0 { return L10n.tr("Only when you press Update") }
        if let when = filters.lastUpdated {
            let fmt = RelativeDateTimeFormatter()
            fmt.unitsStyle = .short
            fmt.locale = Locale(identifier: L10n.tongueTag ?? Locale.current.identifier)
            return L10n.tr("Last updated %@", fmt.localizedString(for: when, relativeTo: Date()))
        }
        return L10n.tr("Uses the lists shipped with Kenos until the first update")
    }
    enum Page: String, CaseIterable, Identifiable {
        case general, tabs, extensions, passwords, downloads, privacy, about
        var id: String { rawValue }
        var title: String {
            switch self {
            case .general: return L10n.tr("settings.general")
            case .tabs: return L10n.tr("settings.tabs")
            case .extensions: return L10n.tr("settings.extensions")
            case .passwords: return L10n.tr("settings.passwords")
            case .downloads: return L10n.tr("settings.downloads")
            case .privacy: return L10n.tr("settings.privacy")
            case .about: return L10n.tr("settings.about")
            }
        }
    }

    private static let width: CGFloat = 720
    private static let height: CGFloat = 540

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Palette.hairline).frame(height: 1)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    switch page {
                    case .general: general
                    case .tabs: tabs
                    case .extensions: ExtensionsPage(browser: browser)
                    case .passwords: passwords
                    case .downloads: downloads
                    case .privacy: privacy
                    case .about: about
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: SettingsPanel.width, height: SettingsPanel.height)
        .background(Palette.ground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 34, y: 12)
        .onChange(of: page) { _, page in Store.settings.set(page.rawValue, forKey: "settings.page") }
        .localized()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L10n.tr("settings.title"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 0)
                Door(icon: "xmark", help: L10n.tr("Done   esc")) { browser.tuning = false }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Page.allCases) { item in
                        Chip(title: item.title, on: page == item) { page = item }
                    }
                }
                // Room past the last chip so it can scroll fully into view
                // instead of sitting flush against the clipped edge.
                .padding(.trailing, 8)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private struct Chip: View {
        let title: String
        let on: Bool
        let act: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: act) {
                Text(verbatim: title)
                    .font(.system(size: 12.5, weight: on ? .medium : .regular))
                    .foregroundStyle(on ? Palette.ink : (hovering ? Palette.ink.opacity(0.8) : Palette.muted))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(on ? Palette.wash : (hovering ? Palette.hover : .clear))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(on ? Palette.hairline : .clear, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: false)
            .onHover { hovering = $0 }
            .animation(Motion.quick, value: hovering)
            .animation(Motion.quick, value: on)
        }
    }

    // MARK: - basics

    private var general: some View {
        Card {
            Line(L10n.tr("Default browser"),
                isDefault ? L10n.tr("Kenos already opens links from other apps") : L10n.tr("Mail, Slack and the rest still send links elsewhere")
            ) {
                if isDefault {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 24)
                } else {
                    Pill(L10n.tr("Make default"), filled: true) {
                        Links.becomeDefault { worked in
                            isDefault = Links.isDefault
                            browser.announce(worked && isDefault ? L10n.tr("Links now open here") : L10n.tr("macOS didn't change it"))
                        }
                    }
                }
            }
            Rule()
            Line(L10n.tr("Search engine"), searchDetail) {
                Picker("", selection: $prefs.engine) {
                    ForEach(Engine.allCases) { engine in
                        Text(engine.title).tag(engine)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            if prefs.engine == .custom {
                ZStack(alignment: .leading) {
                    if prefs.customEngine.isEmpty {
                        Text("https://example.com/search?q=%s")
                            .foregroundStyle(Palette.muted.opacity(0.8))
                    }
                    TextField("", text: $prefs.customEngine)
                        .textFieldStyle(.plain)
                        .foregroundStyle(Palette.ink)
                }
                .font(.system(size: 12.5))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Palette.wash, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .padding(.horizontal, 14)
                .padding(.bottom, 11)
            }
            Rule()
            Line(L10n.tr("Appearance"), L10n.tr("Light, dark, or whatever the Mac is doing — pages follow it too")) {
                Segmented(options: Look.allCases.map { ($0, $0.title) }, selection: $prefs.look)
            }
            Rule()
            Line(L10n.tr("lang.label"), L10n.tr("lang.detail")) {
                Segmented(options: Tongue.allCases.map { ($0, $0.title) }, selection: $prefs.tongue)
            }
            Rule()
            Line(L10n.tr("Correct spelling as you type"), L10n.tr("macOS's autocorrect inside pages — the one that capitalises for you")) {
                Switch(on: $prefs.autocorrect)
            }
            Rule()
            Line(L10n.tr("Peek at a link with a shift-click"), L10n.tr("Its page opens in a panel over the one you're reading. Escape puts it away; the other button keeps it as a tab")) {
                Switch(on: $prefs.peeksLinks)
            }
            Rule()
            Line(L10n.tr("Open links from other apps in a small window"), L10n.tr("To read and close, or keep with Open in Kenos (⌘O)")) {
                Switch(on: $prefs.littleLinks)
            }
            Rule()
            Line(L10n.tr("Show where links go"), L10n.tr("Point at a link and its address shows at the bottom of the page")) {
                Switch(on: $prefs.showsLinks)
            }
            Rule()
            Line(L10n.tr("Scroll with the middle button"), L10n.tr("Click the wheel on a page, then move the mouse up or down to scroll, as on Windows. Click again to stop")) {
                Switch(on: $prefs.autoScroll)
            }
            Rule()
            Line(L10n.tr("Pages at 120 Hz"), L10n.tr("Animations and scrolling in pages at up to 120 frames a second on a screen that can, instead of 60 as in Safari. Uses more battery. Open tabs follow when reloaded")) {
                Switch(on: $prefs.fastPages)
            }
            Rule()
            Line(L10n.tr("Flick the floating video to a corner"), L10n.tr("Two fingers on it send it to the corner or edge they point at, instead of pushing it along. Dragging still puts it anywhere")) {
                Switch(on: $prefs.floatFlicks)
            }
            Rule()
            Line(L10n.tr("Float the video when you switch tabs"), L10n.tr("A video playing on YouTube and the like comes out into its floating window when you go to another tab, and back when you return. ⇧⌘P still floats one by hand")) {
                Switch(on: $prefs.floatsOnLeave)
            }
            Rule()
            Line(L10n.tr("Float the video when you switch apps"), L10n.tr("A video playing on the site you're on comes out into its floating window as another app comes to the front, and goes back into its tab when you return")) {
                Switch(on: $prefs.floatsAway)
            }
            Rule()
            Line(L10n.tr("Let a script drive Kenos"), L10n.tr("A local socket for testing. Its tabs open beside yours with a flask on them and never take over — see ./bench")) {
                Switch(on: $prefs.bench)
            }
        }
    }

    private var searchDetail: String {
        guard prefs.engine == .custom else { return L10n.tr("Where words that aren't an address go") }
        guard Engine.accepts(prefs.customEngine) else {
            return L10n.tr("An http or https address with %s where the words go. Until then, Google")
        }
        return L10n.tr("Words go to %@", prefs.engine.name(custom: prefs.customEngine))
    }

    // MARK: - layout

    private var tabs: some View {
        Card {
            Line(L10n.tr("Sidebar tabs"), L10n.tr("A column on the left instead of a strip across the top. Drag the edge to resize; double-click to reset.")) {
                Switch(on: Binding(
                    get: { prefs.sidebar },
                    set: { on in withAnimation(Motion.glide) { prefs.sidebar = on } }
                ))
            }
            if prefs.sidebar {
                Rule()
                Line(L10n.tr("Hide the sidebar until the pointer reaches the edge"), L10n.tr("The page takes the whole window; push against its left edge for the tabs. ⌘S keeps them out.")) {
                    Switch(on: $prefs.sideHides)
                }
            } else {
                Rule()
                Line(L10n.tr("Tabs along the bottom"), L10n.tr("The strip sits under the page instead of above it. Traffic lights stay at the top.")) {
                    Switch(on: Binding(
                        get: { prefs.chromeBottom },
                        set: { on in withAnimation(Motion.glide) { prefs.chromeBottom = on } }
                    ))
                }
            }
            Rule()
            Line(L10n.tr("Tabs show"), L10n.tr("Beside the title, and on a pinned square")) {
                Segmented(options: Glyph.allCases.map { ($0, $0.title) }, selection: $prefs.glyph)
            }
            Rule()
            Line(L10n.tr("Show the bookmarks bar"), L10n.tr("Your bookmarks in a row above the page, folders opening as menus. It folds away with the tabs")) {
                Switch(on: $prefs.bookmarksBar)
            }
            Rule()
            Line(L10n.tr("Show how far you've read"), L10n.tr("The tab you're on fills with grey as you scroll down the page")) {
                Switch(on: $prefs.showsReading)
            }
            Rule()
            Line(L10n.tr("Sleep tabs you aren't using"), L10n.tr("After half an hour away they come back where you left them. Pinned tabs, sound, calls and anything typed stay awake.")) {
                Switch(on: $prefs.sleepsTabs)
            }
            Rule()
            Line(L10n.tr("Spaces"), L10n.tr("Separate sets of tabs, signed in where the others are or starting afresh, switched with ⌃1–⌃9, two fingers sideways over the column, or the space's icon. Mission Control's own ⌃1–⌃9, if you turned them on, take those keys first.")) {
                Switch(on: $prefs.usesSpaces)
            }
        }
    }

    // MARK: - passwords

    /// Says so when a password manager extension has taken the saving over.
    private var savingDetail: String {
        if #available(macOS 15.4, *), let name = Extensions.shared.passwordSavingTakenBy {
            return "\(name) does the saving — it asked Kenos not to offer"
        }
        return L10n.tr("Asked once per site, never again for a site you refuse")
    }

    private var passwords: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card {
                Line(L10n.tr("Your passwords"), L10n.tr("In the macOS keychain, shown with Touch ID")) {
                    Pill(L10n.tr("Open…")) {
                        browser.tuning = false
                        browser.managing = true
                    }
                }
                Rule()
                Line(L10n.tr("Offer to save passwords"), savingDetail) {
                    Switch(on: $prefs.savesPasswords)
                }
                Rule()
                Line(L10n.tr("Fill in sign-ins"), L10n.tr("Click a sign-in box and the accounts kept for the site hang from it")) {
                    Switch(on: $prefs.fillsPasswords)
                }
                Rule()
                Line(L10n.tr("Offer passkeys"),
                    !prefs.passkeysPossible
                        ? L10n.tr("This build can’t use passkeys — sites will keep using passwords")
                        : Passkeys.access == .denied
                        ? L10n.tr("macOS was told no — System Settings › Privacy & Security › Passkeys Access for Web Browsers")
                        : L10n.tr("Touch ID or an iCloud passkey, on sites that offer one")
                ) {
                    Switch(on: $prefs.passkeys)
                }
                if !Vault.never.isEmpty {
                    Rule()
                    Line(L10n.tr("Sites never asked"), L10n.tr("%d sites told to stop offering", Vault.never.count)) {
                        Pill(L10n.tr("Forget")) {
                            Vault.never = []
                            browser.announce(L10n.tr("Every site can ask again"))
                        }
                    }
                }
            }
            Card {
                Line(L10n.tr("Bring yours in"), L10n.tr("From Dia, Chrome, Arc, Brave or Edge on this Mac — nothing leaves it")) {
                    Pill(L10n.tr("Import…")) {
                        browser.tuning = false
                        browser.managing = true
                    }
                }
            }
        }
    }

    // MARK: - downloads

    private var downloads: some View {
        Card {
            Line(L10n.tr("Save to"), prefs.downloads.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) {
                Pill(L10n.tr("Change…")) { chooseFolder() }
            }
            Rule()
            Line(L10n.tr("Ask where to save each file")) {
                Switch(on: $prefs.asksWhereToSave)
            }
        }
    }

    // MARK: - privacy

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card {
                Line(L10n.tr("Block ads and trackers"),
                    shield.trouble
                        ?? (shield.ruleCount > 0
                            ? "\(shield.ruleCount) rules · \(shield.listSource)"
                            : L10n.tr("uBlock Origin lists, blocked before they load"))
                ) {
                    Switch(on: $prefs.shielded)
                }
                if let trouble = shield.trouble {
                    Rule()
                    Line(trouble, L10n.tr("Nothing is being blocked until this clears — try again, or restart Kenos")) {
                        Pill(L10n.tr("Try again")) { shield.compile() }
                    }
                }
                Rule()
                Line(L10n.tr("Filter lists"),
                    filters.lastError
                        ?? (filters.updating
                            ? L10n.tr("Downloading from uBlock…")
                            : filterDetail)
                ) {
                    if filters.updating {
                        ProgressView().controlSize(.small)
                    } else {
                        Pill(L10n.tr("Update now")) {
                            Task { await FilterLists.shared.refresh(force: true) }
                        }
                    }
                }
                Rule()
                Line(L10n.tr("Check for list updates"), L10n.tr("How often Kenos re-downloads EasyList, EasyPrivacy and uBlock’s own filters")) {
                    Segmented(
                        options: [
                            (24.0, L10n.tr("Daily")),
                            (168.0, L10n.tr("Weekly")),
                            (0.0, L10n.tr("Manual")),
                        ],
                        selection: $prefs.shieldListHours
                    )
                }
                if let host = browser.hereHost, prefs.shielded, shield.trouble == nil {
                    Rule()
                    Line(L10n.tr("Block on %@", host), L10n.tr("Turn off here if the site breaks — the page reloads")) {
                        Switch(on: Binding(
                            get: { !Shield.shared.isPaused(on: host) },
                            set: { on in
                                Shield.shared.pause(host, !on)
                                browser.reload()
                            }
                        ))
                    }
                }
                Rule()
                Line(L10n.tr("Camera and microphone"), L10n.tr("What each site was allowed or refused")) {
                    Pill(L10n.tr("Forget choices")) { browser.forgetCaptureChoices() }
                }
            }
            Card {
                Line(L10n.tr("History"), L10n.tr("Every address you have been to")) {
                    Pill(L10n.tr("Clear")) { browser.clearHistory() }
                }
                Rule()
                Line(L10n.tr("Cookies and sign-ins"), L10n.tr("Signs you out of every site")) {
                    Pill(L10n.tr("Sign out of everything")) { browser.clearSites() }
                }
                Rule()
                Line(L10n.tr("Cache"), L10n.tr("Only what was fetched to draw pages")) {
                    Pill(L10n.tr("Clear")) { browser.clearCache() }
                }
            }
        }
    }

    // MARK: - about

    private var about: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                KenosBadge(size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Kenos")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text("Κενός")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                    Text(L10n.tr("version %@", Updater.version))
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                    Text(L10n.tr("© 2026 Mikhail Matveev"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.faint)
                    Text(L10n.tr("Published by Elizaveta Fragner"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.faint)
                }
            }
            .padding(.bottom, 2)

            Card {
                Line(L10n.tr("Website"), "kenos.rh1.tech") {
                    Pill(L10n.tr("Open")) {
                        if let url = URL(string: "https://kenos.rh1.tech") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }

            Card {
                Line(versionTitle, versionDetail) { versionControl }
                Rule()
                Line(L10n.tr("Install updates on its own"), L10n.tr("Off, Kenos still looks once a day and tells you, and installs only when you press Install")) {
                    Switch(on: $prefs.installsUpdates)
                }
                Rule()
                Line(L10n.tr("Found something wrong?"), L10n.tr("Opens a draft with the version already in it")) {
                    Pill(L10n.tr("Send Feedback")) { Links.writeFeedback() }
                }
            }

            Card {
                Shortcut("⌘L", L10n.tr("Address"))
                Rule()
                Shortcut("⌘K", L10n.tr("Switch tab"))
                Rule()
                Shortcut("⌘T  ⌘W  ⇧⌘T", L10n.tr("New, close, reopen tab"))
                Rule()
                Shortcut("⇧⌘V", L10n.tr("Paste and go"))
                Rule()
                Shortcut("⇧⌘C", L10n.tr("Copy address"))
                Rule()
                Shortcut("⌃⇥  ⌘1–9", L10n.tr("Next tab, a tab by its place"))
                Rule()
                Shortcut("⇧⌘S", L10n.tr("Tabs in a sidebar"))
                Rule()
                Shortcut("⌘S", L10n.tr("Fold the sidebar away"))
                Rule()
                Shortcut("⇧⌘R", L10n.tr("Reading mode"))
                Rule()
                Shortcut("⇧⌘H", L10n.tr("Hide something on this site"))
                Rule()
                Shortcut("⇧⌘P", L10n.tr("Float the video"))
            }
        }
    }

    /// The version line follows the newer build from found to fetched to
    /// in place; with none, it is simply this one.
    private var versionTitle: String {
        switch updater.stage {
        case .none: return L10n.tr("Updates")
        case .fetching(let next): return L10n.tr("Kenos %@ is downloading…", next.version)
        case .ready(let next): return L10n.tr("Kenos %@ is ready", next.version)
        case .offered(let next), .waiting(let next): return L10n.tr("Kenos %@ is out", next.version)
        }
    }

    private var versionDetail: String {
        switch updater.stage {
        case .none:
            return updater.lastChecked.map {
                let relative = $0.formatted(.relative(presentation: .named)
                    .locale(Locale(identifier: L10n.tongueTag ?? Locale.current.identifier)))
                return L10n.tr("Checked %@ — once a day on its own", relative)
            }
                ?? L10n.tr("Checked once a day on its own")
        case .fetching(let next):
            return next.notes ?? L10n.tr("Quietly, in the background — nothing you have set is touched")
        case .ready(let next):
            return next.notes ?? L10n.tr("It's there the next time you open Kenos")
        case .offered(let next):
            return next.notes ?? L10n.tr("Open the disk image, the same as the first time")
        case .waiting(let next):
            return next.notes ?? L10n.tr("Checked and put in place when you press Install")
        }
    }

    @ViewBuilder
    private var versionControl: some View {
        switch updater.stage {
        case .none:
            Pill(updater.checking ? L10n.tr("Checking…") : L10n.tr("Check now")) {
                updater.check { found in
                    if found == nil { browser.announce(L10n.tr("This is the latest one")) }
                }
            }
            .disabled(updater.checking)
        case .fetching:
            Ring(size: 12)
        case .ready:
            Pill(L10n.tr("Relaunch now"), filled: true) { updater.relaunch() }
        case .offered(let next):
            Pill(L10n.tr("Download"), filled: true) {
                browser.tuning = false
                browser.open(next.dmg, foreground: true)
            }
        case .waiting:
            Pill(L10n.tr("Install"), filled: true) { updater.install() }
        }
    }

    // MARK: - doing

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = prefs.downloads
        panel.prompt = L10n.tr("Use this folder")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        prefs.downloads = url
    }

    // MARK: - pieces

    /// A keystroke and what it does.
    private struct Shortcut: View {
        let keys: String
        let does: String
        init(_ keys: String, _ does: String) { self.keys = keys; self.does = does }

        var body: some View {
            HStack {
                Text(does)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text(keys)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
    }
}

/// A row of choices in a grey track, one of them lifted out in white. The
/// white slides to the one you pick rather than appearing there.
struct Segmented<Option: Hashable>: View {
    let options: [(Option, String)]
    @Binding var selection: Option
    /// True when the control has the whole width to itself, so the choices
    /// share it evenly instead of each taking only what its word needs.
    var wide = false

    @Namespace private var slide

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { option, title in
                Text(title)
                    .font(.system(size: 11.5, weight: option == selection ? .medium : .regular))
                    .foregroundStyle(option == selection ? Palette.ink : Palette.muted)
                    .lineLimit(1)
                    .fixedSize(horizontal: !wide, vertical: false)
                    .frame(maxWidth: wide ? .infinity : nil)
                    .padding(.horizontal, wide ? 4 : 10)
                    .padding(.vertical, 5)
                    .background {
                        if option == selection {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Palette.ground)
                                .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                                .matchedGeometryEffect(id: "chosen", in: slide)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .onTapGesture {
                        withAnimation(Motion.settle) { selection = option }
                    }
            }
        }
        .padding(2)
        .background(Palette.wash, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .animation(Motion.settle, value: selection)
    }
}

/// On or off, in ink rather than in blue.
struct Switch: View {
    @Binding var on: Bool

    var body: some View {
        Capsule()
            .fill(on ? Palette.ink : Palette.faint)
            .frame(width: 30, height: 18)
            .overlay(alignment: on ? .trailing : .leading) {
                Circle()
                    .fill(Palette.ground)
                    .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                    .padding(2)
            }
            .contentShape(Capsule())
            .onTapGesture { withAnimation(Motion.settle) { on.toggle() } }
            .animation(Motion.settle, value: on)
    }
}

/// A small capsule that does one thing. Outlined by default; filled in ink
/// when it is the thing you came here to press.
struct Pill: View {
    let title: String
    var filled = false
    var tint: Color = Palette.ink
    let action: () -> Void

    @State private var hovering = false

    init(_ title: String, filled: Bool = false, tint: Color = Palette.ink, action: @escaping () -> Void) {
        self.title = title
        self.filled = filled
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5))
                .foregroundStyle(filled ? Palette.ground : tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(filled ? Palette.ink : (hovering ? Palette.hover : Palette.ground), in: Capsule())
                .overlay(Capsule().strokeBorder(filled ? .clear : Palette.hairline, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
    }
}
