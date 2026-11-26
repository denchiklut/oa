import AppKit
import SwiftUI

/// Arc's Space menu, in its order. AppKit's, as Arc's is: a SwiftUI menu can't show a submenu disabled. A Library
/// card's leaves out Manage Spaces…, as Arc's does. What Oa doesn't have yet is listed disabled.
///
/// As seen in Arc, the card of a window's own Space lists them all enabled too, with Show Space Header where Export
/// is. Oa's own: what acts on the Space is off there, as what Arc's do to such a Space wasn't tried.
@MainActor
struct SpaceMenu {
    let model: WindowModel
    let space: SidebarSpace
    var inLibrary = false
    let changeIcon: () -> Void
    let rename: () -> Void
    let editTheme: () -> Void

    func make() -> NSMenu {
        let global = model.state.isGlobal(space.id)
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.items = [
            MenuActionItem("Change Space Icon…", global ? changeIcon : nil),
            MenuActionItem("Rename Space…", global ? rename : nil),
            MenuActionItem("Edit Theme Color…", global ? editTheme : nil),
            MenuActionItem("Set Profile", submenu: profiles(), enabled: global),
            .separator(),
            MenuActionItem("New Folder", enabled: global) { [model, space] in
                model.exitLibrary()
                model.createFolder(in: space.id, startEditing: true)
            },
            MenuActionItem("Live Folders", submenu: NSMenu(), enabled: false),
            .separator(),
            MenuActionItem("Share Space…"),
        ]
        if global {
            menu.addItem(
                MenuActionItem("Export “\(space.name)” into Folder", submenu: NSMenu(), enabled: false))
        } else {
            menu.addItem(.separator())
            menu.addItem(MenuActionItem("Show Space Header"))
        }
        menu.addItem(.separator())
        if !inLibrary {
            menu.addItem(MenuActionItem("Manage Spaces…") { [model] in model.viewLibrary(.spaces) })
            menu.addItem(.separator())
        }
        let delete = MenuActionItem("Delete Space") { [model, space] in SpaceDeletion.confirm(space, in: model) }
        delete.isEnabled = global && model.state.spaces.count > 1
        menu.addItem(delete)
        return menu
    }

    /// As Arc, by name here, where Settings and Change Profile keep the engine's order.
    private func profiles() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for profile in model.profiles.sorted(by: { $0.name < $1.name }) {
            let item = MenuActionItem(profile.name) { [model, space] in
                _ = ProfileDialogUtils.confirmSwitch([space.id], to: profile.id, in: model)
            }
            item.state = profile.id == space.profileID ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(
            MenuActionItem("New Profile…") { [model, space] in
                ProfileDialogUtils.createProfile(checking: [space.id], in: model)
            })
        return menu
    }
}

extension SpaceMenu {
    /// From the sidebar, the icon picker opens at the Space's name.
    init(model: WindowModel, layout: WindowLayoutController, space: SidebarSpace) {
        self.init(model: model, space: space) {
            model.selectSpace(space.id)
            layout.iconPickerSpaceID = space.id
        } rename: {
            if let name = NamePrompt.run("Rename Space", name: space.name) { model.renameSpace(space.id, to: name) }
        } editTheme: {
            model.presentSpaceStyleEditor(for: space.id, from: .sidebar)
        }
    }
}

final class MenuActionItem: NSMenuItem {
    private let handler: (() -> Void)?

    init(_ title: String, submenu: NSMenu? = nil, enabled: Bool = true, _ handler: (() -> Void)? = nil) {
        self.handler = handler
        super.init(title: title, action: handler == nil ? nil : #selector(choose), keyEquivalent: "")
        target = self
        self.submenu = submenu
        isEnabled = enabled && (handler != nil || submenu != nil)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func choose() { handler?() }
}

/// A menu at the pointer, as Arc pops up the Space menu's "⋯" and the toolbar's Split View menu with the click's
/// event.
struct PointerMenuButton<Label: View>: View {
    let menu: () -> NSMenu
    @ViewBuilder let label: Label
    @State private var anchor = Anchor()

    var body: some View {
        Button {
            guard let view = anchor.view, let event = NSApp.currentEvent else { return }
            let menu = menu()
            menu.appearance = view.window?.effectiveAppearance
            NSMenu.popUpContextMenu(menu, with: event, for: view)
        } label: {
            label
        }
        .background(AnchorView(anchor: anchor))
    }

    @MainActor
    private final class Anchor {
        weak var view: NSView?
    }

    private struct AnchorView: NSViewRepresentable {
        let anchor: Anchor

        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            anchor.view = view
            return view
        }

        func updateNSView(_ view: NSView, context: Context) { anchor.view = view }
    }
}

extension View {
    /// Opens the Space menu on a right-click or Control-click over this view, except over views marked with
    /// `spaceMenuExclusion()`. After open-arch: SwiftUI's context menu can't hold an AppKit menu, and a view watching
    /// for it is laid out where it would be, clipped or not, so one off the sidebar is turned off.
    func spaceContextMenu(isEnabled: Bool = true, _ menu: @escaping () -> SpaceMenu) -> some View {
        background(PlatformContextMenu(isEnabled: isEnabled, yieldsToExclusions: true) { menu().make() })
    }

    /// An AppKit menu on a right-click or Control-click over this view, which keeps the Space menu shut, as Arc's
    /// sidebar items have.
    func platformContextMenu(isEnabled: Bool = true, _ menu: @escaping () -> NSMenu) -> some View {
        background(PlatformContextMenu(isEnabled: isEnabled, yieldsToExclusions: false, menu: menu))
            .spaceMenuExclusion()
    }

    /// Keeps the Space menu shut over this view, which has its own.
    func spaceMenuExclusion() -> some View {
        background(SpaceMenuExclusion())
    }
}

private struct PlatformContextMenu: NSViewRepresentable {
    let isEnabled: Bool
    let yieldsToExclusions: Bool
    let menu: () -> NSMenu

    func makeNSView(context: Context) -> PlatformContextMenuView { PlatformContextMenuView() }

    func updateNSView(_ view: PlatformContextMenuView, context: Context) {
        view.menuBuilder = isEnabled ? menu : nil
        view.yieldsToExclusions = yieldsToExclusions
    }

    static func dismantleNSView(_ view: PlatformContextMenuView, coordinator: ()) { view.stopMonitoring() }
}

private final class PlatformContextMenuView: NSView {
    var menuBuilder: (() -> NSMenu)?
    var yieldsToExclusions = false
    private var monitor: Any?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.open(for: event) == true } ? nil : event
        }
    }

    func stopMonitoring() {
        monitor.map(NSEvent.removeMonitor)
        monitor = nil
    }

    private func open(for event: NSEvent) -> Bool {
        guard event.window === window, !isHiddenOrHasHiddenAncestor,
            event.type == .rightMouseDown || event.modifierFlags.contains(.control),
            contains(convert(event.locationInWindow, from: nil)),
            !yieldsToExclusions || !SpaceMenuExclusionView.excludes(event), let menuBuilder
        else { return false }
        let built = menuBuilder()
        built.appearance = window?.effectiveAppearance
        NSMenu.popUpContextMenu(built, with: event, for: self)
        return true
    }
}

private struct SpaceMenuExclusion: NSViewRepresentable {
    func makeNSView(context: Context) -> SpaceMenuExclusionView { SpaceMenuExclusionView() }
    func updateNSView(_ view: SpaceMenuExclusionView, context: Context) {}
}

private extension NSView {
    /// A view in SwiftUI can report a visible rect larger than its bounds.
    func contains(_ point: NSPoint) -> Bool { bounds.contains(point) && visibleRect.contains(point) }
}

private final class SpaceMenuExclusionView: NSView {
    private static let all = NSHashTable<SpaceMenuExclusionView>.weakObjects()

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { Self.all.remove(self) } else { Self.all.add(self) }
    }

    static func excludes(_ event: NSEvent) -> Bool {
        all.allObjects.contains { view in
            view.window === event.window && !view.isHiddenOrHasHiddenAncestor
                && view.contains(view.convert(event.locationInWindow, from: nil))
        }
    }
}
