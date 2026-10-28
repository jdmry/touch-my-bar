import AppKit

/// Running applications as a row of icons. Tap to switch, press and hold
/// to quit. The frontmost app gets a dot under it.
final class DockMode: NSObject, BarMode {

    static let identifier = "dock"
    let title = "Dock"

    private enum Metrics {
        static let iconSize: CGFloat = 24
        static let buttonWidth: CGFloat = 36
        static let holdToQuit: TimeInterval = 0.6
    }

    private let stack: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
        return stack
    }()

    private lazy var scrollView: NSScrollView = {
        let scrollView = NSScrollView()
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.documentView = stack
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
        ])
        return scrollView
    }()

    var view: NSView { scrollView }

    /// Parallel to the buttons in `stack`: index i's button acts on apps[i].
    private var apps: [NSRunningApplication] = []
    private var observers: [NSKeyValueObservation] = []
    private var isActive = false

    // MARK: - BarMode

    func activate() {
        guard !isActive else { return }
        isActive = true

        let center = NSWorkspace.shared.notificationCenter
        for name: NSNotification.Name in [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
        ] {
            center.addObserver(self, selector: #selector(reload), name: name, object: nil)
        }

        reload()
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Contents

    @objc private func reload() {
        // `.regular` drops menu bar agents and daemons, leaving the apps a
        // person would recognise from the real Dock.
        apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .sorted { ($0.launchDate ?? .distantPast) < ($1.launchDate ?? .distantPast) }

        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        for (index, app) in apps.enumerated() {
            stack.addArrangedSubview(makeButton(for: app, at: index))
        }
    }

    private func makeButton(for app: NSRunningApplication, at index: Int) -> NSView {
        let button = NSButton(title: "", target: self, action: #selector(buttonTapped(_:)))
        button.tag = index
        button.bezelStyle = .inline
        button.isBordered = false
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = app.localizedName

        if let icon = app.icon {
            icon.size = NSSize(width: Metrics.iconSize, height: Metrics.iconSize)
            button.image = icon
        }

        // Frontmost app reads as selected; hidden apps are dimmed.
        button.alphaValue = app.isHidden ? 0.4 : 1.0
        if app.isActive {
            button.wantsLayer = true
            button.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.2).cgColor
            button.layer?.cornerRadius = 6
        }

        let hold = NSPressGestureRecognizer(target: self, action: #selector(buttonHeld(_:)))
        hold.minimumPressDuration = Metrics.holdToQuit
        hold.allowedTouchTypes = [.direct]
        button.addGestureRecognizer(hold)

        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: Metrics.buttonWidth).isActive = true

        return button
    }

    // MARK: - Actions

    @objc private func buttonTapped(_ sender: NSButton) {
        guard let app = app(at: sender.tag) else { return }

        if app.isActive {
            app.hide()
        } else {
            app.activate(options: [.activateAllWindows])
        }
    }

    @objc private func buttonHeld(_ gesture: NSPressGestureRecognizer) {
        guard gesture.state == .began,
              let button = gesture.view as? NSButton,
              let app = app(at: button.tag) else { return }

        app.terminate()
    }

    /// The app list is rebuilt on every workspace event, so a tag captured
    /// when the button was made can be stale by the time it fires.
    private func app(at index: Int) -> NSRunningApplication? {
        guard apps.indices.contains(index) else { return nil }
        return apps[index]
    }
}
