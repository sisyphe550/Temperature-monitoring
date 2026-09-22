import AppKit
import SwiftUI

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let presentationModel: PresentationModel
    private weak var actions: PresentationActions?
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var isObserving = false

    init(presentationModel: PresentationModel, actions: PresentationActions) {
        self.presentationModel = presentationModel
        self.actions = actions
        super.init()
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            refreshStatusButton(button)
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
        popover = makePopover()
        startObserving()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func showPopoverForTesting() {
        guard let button = statusItem?.button else {
            return
        }
        togglePopoverVisibility(relativeTo: button)
    }

    func uninstall() {
        isObserving = false
        NotificationCenter.default.removeObserver(self)
        closePopover()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        popover = nil
        statusItem = nil
    }

    @objc private func handleScreenParametersChanged() {
        closePopover()
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            return
        }
        if event.type == .rightMouseUp {
            showContextMenu(from: sender)
            return
        }
        togglePopoverVisibility(relativeTo: sender)
    }

    private func togglePopoverVisibility(relativeTo button: NSStatusBarButton) {
        guard let popover else {
            return
        }
        if popover.isShown {
            popover.close()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        menu.addItem(
            withTitle: "打开主窗口",
            action: #selector(openDashboardFromMenu),
            keyEquivalent: ""
        )
        menu.addItem(
            withTitle: "设置",
            action: #selector(openSettingsFromMenu),
            keyEquivalent: ","
        )
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "退出",
            action: #selector(quitFromMenu),
            keyEquivalent: "q"
        )
        menu.items.forEach { $0.target = self }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    @objc private func openDashboardFromMenu() {
        actions?.openDashboard()
    }

    @objc private func openSettingsFromMenu() {
        actions?.openSettings()
    }

    @objc private func quitFromMenu() {
        actions?.quit()
    }

    private func closePopover() {
        popover?.close()
    }

    private func makePopover() -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: 340, height: 640)
        popover.contentViewController = NSHostingController(
            rootView: TemperaturePopoverView(
                presentationModel: presentationModel,
                actions: actions,
                onClose: { [weak self] in self?.closePopover() }
            )
        )
        return popover
    }

    private func startObserving() {
        guard !isObserving else {
            return
        }
        isObserving = true
        observePresentationState()
    }

    private func observePresentationState() {
        guard isObserving else {
            return
        }
        withObservationTracking {
            _ = presentationModel.state
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.refreshStatusItem()
                self?.observePresentationState()
            }
        }
        refreshStatusItem()
    }

    private func refreshStatusItem() {
        guard let button = statusItem?.button else {
            return
        }
        refreshStatusButton(button)
    }

    private func refreshStatusButton(_ button: NSStatusBarButton) {
        let title = TemperatureFormatting.statusTitle(for: presentationModel.state)
        button.title = title
        button.setAccessibilityIdentifier("status.temperature")
        button.setAccessibilityLabel(title)
        button.setAccessibilityValue(title)
    }
}
