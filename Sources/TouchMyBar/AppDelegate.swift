import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private static let lastModeKey = "lastModeIdentifier"

    private var statusItem: NSStatusItem?

    /// Every mode the app knows about. Adding one here is all it takes for
    /// it to appear in the menu and be selectable.
    private lazy var modes: [BarMode] = [
        DockMode(),
        PetMode(),
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        installStatusItem()

        guard TouchBarController.isSupported else {
            presentUnsupportedAlert()
            return
        }

        TouchBarController.shared.install()

        let saved = UserDefaults.standard.string(forKey: Self.lastModeKey)
        let mode = modes.first { $0.identifier == saved } ?? modes[0]
        select(mode)

        TouchBarController.shared.present()
    }

    func applicationWillTerminate(_ notification: Notification) {
        TouchBarController.shared.uninstall()
    }

    // MARK: - Menu bar

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.grid.1x2",
                                     accessibilityDescription: "Touch My Bar")
        item.menu = makeMenu()
        statusItem = item
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        for (index, mode) in modes.enumerated() {
            let item = NSMenuItem(title: mode.title,
                                  action: #selector(modeSelected(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = mode === TouchBarController.shared.currentMode ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let toggle = NSMenuItem(title: "Show on Touch Bar",
                                action: #selector(togglePresented),
                                keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Touch My Bar",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        return menu
    }

    private func refreshMenu() {
        statusItem?.menu = makeMenu()
    }

    // MARK: - Actions

    @objc private func modeSelected(_ sender: NSMenuItem) {
        guard modes.indices.contains(sender.tag) else { return }
        select(modes[sender.tag])
    }

    private func select(_ mode: BarMode) {
        TouchBarController.shared.setMode(mode)
        UserDefaults.standard.set(mode.identifier, forKey: Self.lastModeKey)
        refreshMenu()
    }

    @objc private func togglePresented() {
        let controller = TouchBarController.shared
        controller.isPresented ? controller.dismiss() : controller.present()
        refreshMenu()
    }

    private func presentUnsupportedAlert() {
        let alert = NSAlert()
        alert.messageText = "Touch Bar unavailable"
        alert.informativeText = """
            This Mac has no Touch Bar, or this version of macOS no longer \
            exposes the private interfaces Touch My Bar relies on.
            """
        alert.alertStyle = .warning
        alert.runModal()
    }
}
