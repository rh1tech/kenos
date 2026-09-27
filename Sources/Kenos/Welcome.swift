import SwiftUI

/// First launch. Four short stops: who we are, what to import, where tabs
/// sit, and whether Kenos takes links from other apps. Skip anytime.
struct WelcomePanel: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences

    @State private var page = 0
    @State private var forward = true

    // Bringing things over. Nil until one is picked, which means the first:
    // finding them looks through each browser's folders, and as an initial
    // value that ran every time the panel was made, the first window's
    // included, for a page that isn't showing yet.
    @State private var source: Chromium.Source?
    @State private var wantsPasswords = true
    @State private var wantsHistory = true
    @State private var wantsBookmarks = true
    @State private var bringing = false
    @State private var brought: String?

    // The default browser.
    @State private var isDefault = Links.isDefault
    @State private var asked = false

    private let pages = 4

    var body: some View {
        ZStack {
            Palette.ground.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                ZStack {
                    switch page {
                    case 0: welcome
                    case 1: bring
                    case 2: hold
                    default: links
                    }
                }
                .frame(maxWidth: 520)
                .id(page)
                .transition(.asymmetric(
                    insertion: .offset(x: forward ? 40 : -40).combined(with: .opacity),
                    removal: .offset(x: forward ? -40 : 40).combined(with: .opacity)
                ))
                Spacer(minLength: 0)
                foot
            }
            .padding(40)
        }
        .animation(Motion.glide, value: page)
        .transition(.opacity)
        .localized()
    }

    // MARK: - the pages

    private var welcome: some View {
        VStack(spacing: 22) {
            Plate(size: 72)
            VStack(spacing: 10) {
                Text("Kenos")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(Palette.ink)
                Text(L10n.tr("Built on the WebKit already in macOS — Safari’s engine, without Safari’s chrome. Extensions when you want them. Ads blocked before they load."))
                    .font(.system(size: 14.5))
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 420)
            }
        }
    }

    private var bring: some View {
        VStack(alignment: .leading, spacing: 22) {
            heading(L10n.tr("Carry over what you already have."), L10n.tr("Passwords go into the keychain on this Mac. Bookmarks keep their folders. History is only so the address field can finish what you start typing."))

            let sources = Chromium.installed()
            if sources.isEmpty {
                Text(L10n.tr("No Chrome-family browser found here — you can skip this."))
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.faint)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    if sources.count > 1 {
                        Segmented(
                            options: sources.map { ($0, $0.name) },
                            selection: Binding(get: { source ?? sources[0] }, set: { source = $0 })
                        )
                    } else {
                        Text(L10n.tr("From %@", sources[0].name))
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.muted)
                    }
                    Choice(L10n.tr("Passwords"), L10n.tr("Keychain only — nothing is uploaded"), on: $wantsPasswords)
                    Choice(L10n.tr("Bookmarks"), L10n.tr("Folders included"), on: $wantsBookmarks)
                    Choice(L10n.tr("History"), L10n.tr("Recent addresses for the omnibox"), on: $wantsHistory)
                }

                HStack(spacing: 12) {
                    Big(bringing ? L10n.tr("Importing…") : L10n.tr("Import"), filled: true) { bringAll() }
                        .disabled(bringing || brought != nil || !(wantsPasswords || wantsHistory || wantsBookmarks))
                    if bringing { Ring(size: 10) }
                    if let brought {
                        Text(brought)
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.muted)
                            .transition(.opacity)
                    }
                }
                .animation(Motion.settle, value: brought)
            }
        }
    }

    private var hold: some View {
        VStack(alignment: .leading, spacing: 22) {
            heading(L10n.tr("Where the tabs live."), L10n.tr("A strip across the top, or a column on the left you can tuck away. Change it later with ⇧⌘S."))
            HStack(spacing: 12) {
                Way(title: L10n.tr("Across the top"), sidebar: false, chosen: !prefs.sidebar) {
                    withAnimation(Motion.glide) { prefs.sidebar = false }
                }
                Way(title: L10n.tr("Down the side"), sidebar: true, chosen: prefs.sidebar) {
                    withAnimation(Motion.glide) { prefs.sidebar = true }
                }
            }
            HStack(spacing: 12) {
                Text(L10n.tr("Favicons or letters"))
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.muted)
                Segmented(options: Glyph.allCases.map { ($0, $0.title) }, selection: $prefs.glyph)
            }
        }
    }

    private var links: some View {
        VStack(alignment: .leading, spacing: 22) {
            heading(L10n.tr("Optional: make Kenos home."), L10n.tr("Mail, Messages, Slack — macOS sends those clicks to the default browser. That can be Kenos, or not."))
            HStack(spacing: 12) {
                if isDefault {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .medium))
                        Text(L10n.tr("Kenos is already the default"))
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.ink)
                } else {
                    Big(L10n.tr("Use as default browser"), filled: true) {
                        asked = true
                        Links.becomeDefault { _ in isDefault = Links.isDefault }
                    }
                    if asked, !isDefault {
                        Text(L10n.tr("macOS shows its own confirmation"))
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.faint)
                    }
                }
            }
            .animation(Motion.settle, value: isDefault)

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.tr("Handy later"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.faint)
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .padding(.top, 6)
                Key("⌘T", L10n.tr("New tab — type an address or a search."))
                Key("⌘L", L10n.tr("Focus the address field."))
                Key("⌘,", L10n.tr("Settings — layout, shield, passwords, updates."))
                Key("⇧⌘S", L10n.tr("Tabs across the top ↔ down the side."))
                Key("⌘O", L10n.tr("Keep a link that arrived in a small window."))
            }
        }
    }

    // MARK: - the bottom edge

    private var foot: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                ForEach(0..<pages, id: \.self) { i in
                    Circle()
                        .fill(i == page ? Palette.ink : Palette.faint.opacity(0.6))
                        .frame(width: 6, height: 6)
                }
            }
            Spacer()
            if page > 0 {
                Button(L10n.tr("Back")) { forward = false; page -= 1 }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.muted)
            }
            if page < pages - 1 {
                Button(L10n.tr("Skip")) { finish() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.muted)
            }
            Big(page < pages - 1 ? L10n.tr("Next") : L10n.tr("Open Kenos"), filled: true) {
                if page < pages - 1 { forward = true; page += 1 } else { finish() }
            }
            .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: 520)
    }

    // MARK: - doing

    private func bringAll() {
        guard let source = source ?? Chromium.installed().first else { return }
        bringing = true
        var lines: [String] = []
        let group = DispatchGroup()
        if wantsPasswords {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let outcome = Result { try Chromium.read(source) }
                DispatchQueue.main.async {
                    switch outcome {
                    case .success(let found):
                        var kept = 0
                        for login in found.logins
                        where Vault.save(host: login.host, user: login.user, password: login.password, used: login.used, clear: login.clear) {
                            kept += 1
                        }
                        var never = Vault.never
                        found.never.forEach { never.insert($0) }
                        Vault.never = never
                        lines.append(L10n.tr("%d passwords", kept))
                    case .failure(Chromium.Trouble.noPassphrase):
                        lines.append(L10n.tr("passwords: macOS didn't hand over the key — allow it and try again"))
                    case .failure:
                        lines.append(L10n.tr("passwords: nothing readable"))
                    }
                    group.leave()
                }
            }
        }
        if wantsBookmarks {
            lines.append(L10n.tr("%d bookmarks", browser.takeBookmarks(from: source)))
        }
        if wantsHistory {
            group.enter()
            browser.takePlaces(from: source) { count in
                lines.append(L10n.tr("%d places", count))
                group.leave()
            }
        }
        group.notify(queue: .main) {
            bringing = false
            brought = lines.joined(separator: " · ")
            browser.relist()
        }
    }

    private func finish() {
        prefs.welcomed = true
        withAnimation(Motion.settle) { browser.welcoming = false }
    }

    private func heading(_ title: String, _ line: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Palette.ink)
            Text(line)
                .font(.system(size: 14))
                .foregroundStyle(Palette.muted)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - pieces

    /// Kenos's black-hole badge for the welcome hero.
    private struct Plate: View {
        let size: CGFloat
        var body: some View {
            KenosBadge(size: size)
        }
    }

    private struct Big: View {
        let title: String
        var filled = false
        let act: () -> Void
        @State private var hovering = false

        init(_ title: String, filled: Bool = false, act: @escaping () -> Void) {
            self.title = title
            self.filled = filled
            self.act = act
        }

        var body: some View {
            Button(action: act) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(filled ? Palette.ground : Palette.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(filled ? Palette.ink : (hovering ? Palette.hover : Palette.wash), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
        }
    }

    private struct Choice: View {
        let title: String
        let detail: String
        @Binding var on: Bool

        init(_ title: String, _ detail: String, on: Binding<Bool>) {
            self.title = title
            self.detail = detail
            _on = on
        }

        var body: some View {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13.5)).foregroundStyle(Palette.ink)
                    Text(detail).font(.system(size: 11.5)).foregroundStyle(Palette.faint)
                }
                Spacer()
                Switch(on: $on)
            }
        }
    }

    /// One of the two ways, as a small drawing of the window.
    private struct Way: View {
        let title: String
        let sidebar: Bool
        let chosen: Bool
        let pick: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: pick) {
                VStack(alignment: .leading, spacing: 10) {
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.ground)
                        if sidebar {
                            HStack(spacing: 0) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 3) { ForEach(0..<3, id: \.self) { _ in Circle().fill(Palette.faint).frame(width: 5, height: 5) } }
                                        .padding(.bottom, 4)
                                    ForEach(0..<4, id: \.self) { i in
                                        RoundedRectangle(cornerRadius: 3).fill(i == 0 ? Palette.wash : Palette.hover).frame(height: 8)
                                    }
                                }
                                .padding(8)
                                .frame(width: 62)
                                Rectangle().fill(Palette.hairline).frame(width: 1)
                                Spacer()
                            }
                        } else {
                            HStack(spacing: 3) {
                                HStack(spacing: 3) { ForEach(0..<3, id: \.self) { _ in Circle().fill(Palette.faint).frame(width: 5, height: 5) } }
                                    .padding(.trailing, 6)
                                ForEach(0..<4, id: \.self) { i in
                                    RoundedRectangle(cornerRadius: 3).fill(i == 0 ? Palette.wash : Palette.hover).frame(width: 30, height: 8)
                                }
                            }
                            .padding(8)
                        }
                    }
                    .frame(height: 110)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
                    Text(title)
                        .font(.system(size: 13, weight: chosen ? .medium : .regular))
                        .foregroundStyle(chosen ? Palette.ink : Palette.muted)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(chosen ? Palette.wash : (hovering ? Palette.hover : .clear))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(chosen ? Palette.ink.opacity(0.35) : Palette.hairline, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(Motion.quick, value: hovering)
            .animation(Motion.settle, value: chosen)
        }
    }

    private struct Key: View {
        let keys: String
        let what: String
        init(_ keys: String, _ what: String) { self.keys = keys; self.what = what }
        var body: some View {
            HStack(spacing: 10) {
                Text(keys)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Palette.wash, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .frame(minWidth: 44)
                Text(what).font(.system(size: 13)).foregroundStyle(Palette.muted)
            }
        }
    }
}
