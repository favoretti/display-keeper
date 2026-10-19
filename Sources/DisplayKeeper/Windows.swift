import AppKit
import SwiftUI

/// One reusable window per screen. Accessory apps are never frontmost on their own, so showing a
/// window also activates the app.
@MainActor
final class WindowPresenter: NSObject, NSWindowDelegate {
    private let window: NSWindow

    init(window: NSWindow, autosaveName: String) {
        self.window = window
        super.init()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName(autosaveName)
    }

    convenience init<Content: View>(title: String, autosaveName: String, resizable: Bool = false, content: Content) {
        let host = NSHostingController(rootView: content)
        host.sizingOptions = resizable ? [.minSize] : [.preferredContentSize]
        var style: NSWindow.StyleMask = [.titled, .closable]
        if resizable { style.insert(.resizable); style.insert(.miniaturizable) }
        let window = NSWindow(contentRect: .zero, styleMask: style, backing: .buffered, defer: false)
        window.contentViewController = host
        window.title = title
        self.init(window: window, autosaveName: autosaveName)
    }

    func show() {
        NSApp.activateApp()
        window.makeKeyAndOrderFront(nil)
    }
}

/// Toolbar-style preferences window: one tab per pane, SF Symbol icons, resizes to each pane.
@MainActor
final class SettingsWindowController {
    enum Tab: String, CaseIterable { case general, layouts, updates }

    private let tabs: NSTabViewController
    let presenter: WindowPresenter

    init(settings: AppSettings, layouts: LayoutsModel, updater: UpdaterModel) {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.canPropagateSelectedChildViewControllerTitle = false
        self.tabs = tabs
        func add<V: View>(_ tab: Tab, _ label: String, _ symbol: String, _ view: V) {
            let host = NSHostingController(rootView: view)
            host.sizingOptions = [.preferredContentSize]
            let item = NSTabViewItem(viewController: host)
            item.identifier = tab.rawValue
            item.label = label
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            tabs.addTabViewItem(item)
        }
        add(.general, "General", "gearshape", GeneralSettingsView(settings: settings))
        add(.layouts, "Layouts", "rectangle.3.group", LayoutsSettingsView(layouts: layouts, settings: settings))
        add(.updates, "Updates", "arrow.triangle.2.circlepath", UpdatesSettingsView(updater: updater))

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.title = "Display Keeper Settings"
        window.toolbarStyle = .preference
        presenter = WindowPresenter(window: window, autosaveName: "SettingsWindow")
    }

    func show(_ tab: Tab? = nil) {
        if let tab, let i = Tab.allCases.firstIndex(of: tab) { tabs.selectedTabViewItemIndex = i }
        presenter.show()
    }
}
