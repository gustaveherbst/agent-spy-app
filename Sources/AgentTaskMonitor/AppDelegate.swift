import Cocoa
import SwiftUI
import Combine
import AgentTaskCore

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public var statusItem: NSStatusItem!
    public var popover: NSPopover!
    public var appState: MonitorAppState!
    private var cancellables = Set<AnyCancellable>()

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize state
        self.appState = MonitorAppState()

        // Configure popover
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 660, height: 480)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuBarPopupView(state: appState))
        self.popover = popover

        // Configure Status Item
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            updateStatusItemIcon()
        }

        // Observe state changes to update menu bar icon
        appState.$tasks
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItemIcon() }
            .store(in: &cancellables)

        appState.$isConnected
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItemIcon() }
            .store(in: &cancellables)

        appState.$preferences
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItemIcon() }
            .store(in: &cancellables)
    }

    @objc public func statusItemClicked(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        let isRightClick = NSApp.currentEvent?.type == .rightMouseUp

        if isRightClick {
            popover.performClose(sender)
            let menu = NSMenu()
            let titleItem = NSMenuItem(title: "AgentSpy", action: nil, keyEquivalent: "")
            titleItem.isEnabled = false
            menu.addItem(titleItem)
            menu.addItem(NSMenuItem.separator())

            let showItem = NSMenuItem(title: "Show Task Monitor", action: #selector(showPopoverFromMenu), keyEquivalent: "")
            showItem.target = self
            menu.addItem(showItem)

            let prefItem = NSMenuItem(title: "Preferences...", action: #selector(showPreferencesFromMenu), keyEquivalent: ",")
            prefItem.target = self
            menu.addItem(prefItem)

            menu.addItem(NSMenuItem.separator())

            let quitItem = NSMenuItem(title: "Quit AgentSpy", action: #selector(quitApp), keyEquivalent: "q")
            quitItem.target = self
            menu.addItem(quitItem)

            statusItem.menu = menu
            button.performClick(nil)
            DispatchQueue.main.async { [weak self] in
                self?.statusItem.menu = nil
            }
        } else {
            togglePopover(sender)
        }
    }

    @objc public func showPopoverFromMenu() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    @objc public func showPreferencesFromMenu() {
        appState.isPreferencesPresented = true
        showPopoverFromMenu()
    }

    @objc public func quitApp() {
        NSApp.terminate(nil)
    }

    @objc public func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func updateStatusItemIcon() {
        guard let button = statusItem.button else { return }

        let isConn = appState.isConnected
        let attnCount = appState.attentionTasks.count
        let activeCount = appState.activeTasks.count

        let symbolName: String
        if !isConn {
            symbolName = "bolt.slash"
        } else if attnCount > 0 {
            symbolName = "exclamationmark.circle.fill"
        } else if activeCount > 0 {
            symbolName = "circle.inset.filled"
        } else {
            symbolName = "sparkles"
        }

        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Agent Task Monitor")?.withSymbolConfiguration(config) {
            image.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeft
        }

        // Active task count badge
        if appState.preferences.showActiveCount && activeCount > 0 {
            button.title = " \(activeCount)"
        } else {
            button.title = ""
        }
    }
}
