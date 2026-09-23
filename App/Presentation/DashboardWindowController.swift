import AppKit
import SwiftUI

@MainActor
final class DashboardWindowController: NSWindowController, NSWindowDelegate {
    private let presentationModel: PresentationModel
    private weak var actions: PresentationActions?

    init(presentationModel: PresentationModel, actions: PresentationActions) {
        self.presentationModel = presentationModel
        self.actions = actions
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "温度监测"
        window.minSize = NSSize(width: 800, height: 560)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: TemperatureDashboard(
                presentationModel: presentationModel,
                actions: actions
            )
        )
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showWindow() {
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        if NSApp.windows.filter({ $0.isVisible && $0 !== sender }).isEmpty {
            NSApp.setActivationPolicy(.accessory)
        }
        return false
    }
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let presentationModel: PresentationModel
    private weak var actions: PresentationActions?

    init(presentationModel: PresentationModel, actions: PresentationActions) {
        self.presentationModel = presentationModel
        self.actions = actions
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "设置"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: SettingsView(
                presentationModel: presentationModel,
                actions: actions
            )
        )
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showWindow() {
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        if NSApp.windows.filter({ $0.isVisible && $0 !== sender }).isEmpty {
            NSApp.setActivationPolicy(.accessory)
        }
        return false
    }
}
