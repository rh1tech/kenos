import SwiftUI

// The bookmarks bar: the top of the bookmarks, in a thin row above the page,
// as Chrome and Safari have one. A folder opens as a menu. More than the row
// holds scrolls sideways.
//
// Off unless asked for — Settings › Tabs, or Bookmarks › Show Bookmarks Bar
// — since the page gives up a strip of its height to it. Shown even when
// empty so the switch is not a no-op before the first bookmark. It goes with
// the tabs when they fold away (⌘S) and when a video takes the screen.
//
// Items are Buttons, not onTapGesture: a tap gesture on macOS eats the right
// click, so the context menu never appears (Remove, Move to, …).

struct BookmarksBar: View {
    @ObservedObject var browser: Browser
    @ObservedObject var bookmarks: Bookmarks

    static let height: CGFloat = 30

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(bookmarks.roots) { node in
                    Item(node: node) {
                        if node.isFolder {
                            BookmarkMenu.shared.popUp(node)
                        } else if let text = node.url, let url = URL(string: text) {
                            browser.visit(url)
                        }
                    } menu: {
                        if !node.isFolder, let text = node.url, let url = URL(string: text) {
                            Button(L10n.tr("Open")) { browser.visit(url) }
                            Divider()
                        }
                        if node.isFolder {
                            Button(L10n.tr("New Folder Inside…")) {
                                browser.newBookmarkFolder(into: node.id)
                            }
                        }
                        let moveTargets = Bookmarks.folders(bookmarks.roots)
                            .filter { !Bookmarks.holds($0.node.id, node) }
                        Menu(L10n.tr("Move to")) {
                            Button(L10n.tr("Top Level")) { bookmarks.move(node.id, into: nil) }
                            if !moveTargets.isEmpty {
                                Divider()
                                ForEach(moveTargets, id: \.node.id) { target in
                                    Button(String(repeating: "   ", count: target.depth) + target.node.title) {
                                        bookmarks.move(node.id, into: target.node.id)
                                    }
                                }
                            }
                        }
                        Divider()
                        Button(node.isFolder ? L10n.tr("Remove Folder") : L10n.tr("Remove Bookmark"), role: .destructive) {
                            bookmarks.remove(node.id)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: BookmarksBar.height, alignment: .leading)
            .contentShape(Rectangle())
            // Empty stretch of the bar — not on the items (those have their own).
            .contextMenu {
                Button(L10n.tr("New Folder…")) { browser.newBookmarkFolder() }
                Button(L10n.tr("Add This Page")) { browser.bookmarkCurrent() }
                    .disabled(browser.active?.isBlank ?? true)
            }
        }
        .frame(height: BookmarksBar.height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.ground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.hairline).frame(height: 1)
        }
    }

    private struct Item<MenuContent: View>: View {
        let node: Bookmark
        let act: () -> Void
        @ViewBuilder let menu: () -> MenuContent
        @State private var hovering = false

        var body: some View {
            Button(action: act) {
                HStack(spacing: 6) {
                    if node.isFolder {
                        Image(systemName: "folder")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.muted)
                    } else {
                        Mark(icon: Favicons.shared.cached(node.host ?? ""), letter: String((node.host ?? "•").prefix(1)).uppercased(), size: 13)
                    }
                    Text(node.title)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .frame(maxWidth: 150, alignment: .leading)
                        .fixedSize(horizontal: true, vertical: false)
                    if node.isFolder {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7.5, weight: .semibold))
                            .foregroundStyle(Palette.faint)
                    }
                }
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(hovering ? Palette.hover : .clear))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help(node.url ?? node.title)
            .contextMenu { menu() }
        }
    }
}
