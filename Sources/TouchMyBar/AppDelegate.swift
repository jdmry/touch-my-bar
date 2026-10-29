import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private static let lastModeKey = "lastModeIdentifier"

    private var statusItem: NSStatusItem?

    /// Every mode the app knows about. Adding one here is all it takes for
    /// it to appear in the menu and be selectable.
    private lazy var modes: [BarMode] = [
        DockMode(),
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

        // With a single mode there is nothing to choose between, so the
        // list only earns its space once there is more than one.
        if modes.count > 1 {
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
        }

        let toggle = NSMenuItem(title: "Show on Touch Bar",
                                action: #selector(togglePresented),
                                keyEquivalent: "")
        toggle.target = self
        // Ticked means our bar is the one on screen. This was never being
        // set, so the item always read unticked.
        toggle.state = TouchBarController.shared.isPresented ? .on : .off
        menu.addItem(toggle)

        let haptics = NSMenuItem(title: "Haptic Feedback",
                                 action: #selector(toggleHaptics),
                                 keyEquivalent: "")
        haptics.target = self
        haptics.state = Haptics.isEnabled ? .on : .off
        // The buzz comes from the trackpad, not the bar; say so rather than
        // leaving someone wondering why it feels like it is in the wrong place.
        haptics.toolTip = "Tap the Taptic Engine when a bar control is used. "
            + "The Touch Bar has no actuator, so it is felt in the trackpad."
        menu.addItem(haptics)

        let strength = NSMenuItem(title: "Haptic Strength", action: nil, keyEquivalent: "")
        let strengthMenu = NSMenu()
        for option in Haptics.Strength.allCases {
            let item = NSMenuItem(title: option.title,
                                  action: #selector(strengthSelected(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.tag = option.rawValue
            item.state = Haptics.strength == option ? .on : .off
            strengthMenu.addItem(item)
        }
        strength.submenu = strengthMenu
        menu.addItem(strength)

        let sound = NSMenuItem(title: "Click Sound",
                               action: #selector(toggleSound),
                               keyEquivalent: "")
        sound.target = self
        sound.state = Haptics.isSoundEnabled ? .on : .off
        sound.toolTip = "Hearing the click does much of the work a tap would, "
            + "given the bar itself cannot produce one."
        menu.addItem(sound)

        menu.addItem(.separator())

        let login = NSMenuItem(title: "Start at Login",
                               action: #selector(toggleLoginItem),
                               keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

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

    @objc private func toggleHaptics() {
        Haptics.isEnabled.toggle()
        // Fire one so the setting demonstrates itself.
        Haptics.tap()
        refreshMenu()
    }

    @objc private func toggleSound() {
        Haptics.isSoundEnabled.toggle()
        if Haptics.isSoundEnabled { Haptics.tap() }
        refreshMenu()
    }

    @objc private func strengthSelected(_ sender: NSMenuItem) {
        guard let option = Haptics.Strength(rawValue: sender.tag) else { return }
        Haptics.strength = option
        // Fire one at the new setting so the choice is audible/tangible.
        Haptics.tap()
        refreshMenu()
    }

    @objc private func toggleLoginItem() {
        LoginItem.setEnabled(!LoginItem.isEnabled)
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
