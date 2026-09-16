import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor let store = ScreenTimeStore()
    @MainActor var statusItem: NSStatusItem!
    @MainActor let popover = NSPopover()

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = AppDelegate.templateSymbol("gauge.medium")
            button.imagePosition = .imageLeading
            button.action = #selector(togglePopover)
            button.target = self
        }

        let hosting = NSHostingController(rootView: ContentView().environmentObject(store))
        hosting.sizingOptions = [.preferredContentSize]
        popover.behavior = .transient
        popover.contentViewController = hosting

        store.onLabelChange = { [weak self] title, symbol in
            guard let button = self?.statusItem?.button else { return }
            button.title = title ?? ""
            button.image = AppDelegate.templateSymbol(symbol)
        }

        store.reload()
    }

    private static func templateSymbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Screen Time")
            ?? NSImage(systemSymbolName: "clock", accessibilityDescription: "Screen Time")
        image?.isTemplate = true
        return image
    }

    @MainActor
    @objc func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    @MainActor
    private func showPopover() {
        store.reload()
        guard let button = statusItem?.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: { $0.scheme == "screentimebar" }) else { return }
        if popover.isShown {
            store.reload()
        } else {
            showPopover()
        }
    }
}
