import AppKit
import TouchBarPrivate

/// Owns the Touch Bar: puts an icon in the Control Strip, and presents the
/// active mode across the rest of the bar no matter which app is frontmost.
///
/// Everything interesting here goes through SPI (see TouchBarPrivate.h), so
/// each entry point checks the selector exists before calling it. If a macOS
/// release drops the SPI the app degrades to "menu bar item that does
/// nothing" rather than crashing on launch.
final class TouchBarController: NSObject, NSTouchBarDelegate {

    static let shared = TouchBarController()

    private enum ItemID {
        static let tray = NSTouchBarItem.Identifier("dev.ctoasap.touchmybar.tray")
        static let content = NSTouchBarItem.Identifier("dev.ctoasap.touchmybar.content")
    }

    /// Placement 1 puts us over the app region while leaving the Control
    /// Strip visible, which is what lets the tray icon toggle us back.
    private static let systemModalPlacement: Int64 = 1

    private(set) var isPresented = false
    private(set) var currentMode: BarMode?

    private let container = NSView()
    private var touchBar: NSTouchBar?
    private var trayItem: NSCustomTouchBarItem?

    // MARK: - Lifecycle

    /// Installs the Control Strip icon. Call once at launch.
    func install() {
        guard Self.isSupported else {
            NSLog("[TouchMyBar] Touch Bar SPI unavailable on this system; nothing to install.")
            return
        }

        DFRSystemModalShowsCloseBoxWhenFrontMost(false)

        let button = NSButton(
            image: NSImage(systemSymbolName: "rectangle.bottomthird.inset.filled", accessibilityDescription: "Touch My Bar")
                ?? NSImage(),
            target: self,
            action: #selector(trayItemTapped)
        )
        button.bezelStyle = .rounded

        let item = NSCustomTouchBarItem(identifier: ItemID.tray)
        item.view = button
        trayItem = item

        NSTouchBarItem.addSystemTrayItem(item)
        DFRElementSetControlStripPresenceForIdentifier(ItemID.tray, true)
    }

    /// Removes the Control Strip icon and dismisses the bar. Call at quit,
    /// otherwise the icon can linger until the next login.
    func uninstall() {
        dismiss()
        if let trayItem {
            DFRElementSetControlStripPresenceForIdentifier(ItemID.tray, false)
            NSTouchBarItem.removeSystemTrayItem(trayItem)
        }
        trayItem = nil
    }

    // MARK: - Modes

    func setMode(_ mode: BarMode) {
        guard mode !== currentMode else { return }

        currentMode?.deactivate()
        currentMode?.view.removeFromSuperview()

        currentMode = mode

        let view = mode.view
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        // Only run the mode's timers and observers while it is on screen.
        if isPresented {
            mode.activate()
        }
    }

    // MARK: - Presentation

    @objc private func trayItemTapped() {
        isPresented ? dismiss() : present()
    }

    func present() {
        guard Self.isSupported, !isPresented else { return }

        let bar = touchBar ?? makeTouchBar()
        touchBar = bar

        NSTouchBar.presentSystemModalTouchBar(
            bar,
            placement: Self.systemModalPlacement,
            systemTrayItemIdentifier: ItemID.tray
        )

        isPresented = true
        currentMode?.activate()
    }

    func dismiss() {
        guard isPresented else { return }

        currentMode?.deactivate()
        NSTouchBar.dismissSystemModalTouchBar(touchBar)
        isPresented = false
    }

    private func makeTouchBar() -> NSTouchBar {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [ItemID.content]
        return bar
    }

    func touchBar(_ touchBar: NSTouchBar,
                  makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard identifier == ItemID.content else { return nil }
        let item = NSCustomTouchBarItem(identifier: identifier)
        item.view = container
        return item
    }

    // MARK: - Availability

    /// True when the SPI we rely on is present. Checked rather than assumed,
    /// because these symbols are undocumented and can disappear.
    static let isSupported: Bool = {
        let barClass: AnyClass = NSTouchBar.self
        let itemClass: AnyClass = NSTouchBarItem.self
        return barClass.responds(to: #selector(NSTouchBar.presentSystemModalTouchBar(_:placement:systemTrayItemIdentifier:)))
            && barClass.responds(to: #selector(NSTouchBar.dismissSystemModalTouchBar(_:)))
            && itemClass.responds(to: #selector(NSTouchBarItem.addSystemTrayItem(_:)))
    }()
}
