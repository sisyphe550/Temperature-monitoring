import AppKit
import SwiftUI

@MainActor
final class StatusItemController {
    private let presentationModel: PresentationModel
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    init(presentationModel: PresentationModel) {
        self.presentationModel = presentationModel
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let title = formattedStatusTitle()
            button.title = title
            button.setAccessibilityIdentifier("status.temperature")
            button.setAccessibilityLabel(title)
            button.setAccessibilityValue(title)
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
        popover = makePopover()
    }

    func uninstall() {
        if let popover, popover.isShown {
            popover.close()
        }
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        popover = nil
        statusItem = nil
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            return
        }
        if event.type == .rightMouseUp {
            showContextMenu(from: sender)
            return
        }
        guard let popover else {
            return
        }
        if popover.isShown {
            popover.close()
        } else if let button = statusItem?.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        menu.addItem(
            withTitle: "退出",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    private func makePopover() -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 340, height: 640)
        popover.contentViewController = NSHostingController(
            rootView: TemperaturePopoverView(presentationModel: presentationModel)
        )
        return popover
    }

    private func formattedStatusTitle() -> String {
        guard case let .running(running)? = presentationModel.state else {
            return "— °C"
        }
        switch running.primaryCPU {
        case let .live(valueC, _), let .cached(valueC, _, _):
            return String(format: "%.1f °C", valueC)
        case .loading, .stale, .unavailable:
            return "— °C"
        }
    }
}
