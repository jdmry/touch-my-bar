import AppKit

/// The Dock as a row of icons: pinned apps whether or not they are running,
/// then anything else currently open. Tap behaves like a Dock click — launch
/// or bring to front. Press and hold quits a running app.
final class DockMode: NSObject, BarMode {

    static let identifier = "dock"
    let title = "Dock"

    private enum Metrics {
        /// The bar is 30pt tall. 28 leaves a 1pt edge so icons do not look
        /// cropped against the bezel; this is the practical ceiling.
        static let iconSize: CGFloat = 28
        /// Wider than the icon: the extra is the touch target, not the art.
        /// The bar fits ~16 of these, well past the number of apps anyone
        /// keeps open, so the width is spent on making them easy to hit.
        static let buttonWidth: CGFloat = 52
        static let spacing: CGFloat = 8
        static let cornerRadius: CGFloat = 7
        static let holdToQuit: TimeInterval = 0.6
        static let separatorInset: CGFloat = 10
    }

    private let stack: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = Metrics.spacing
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
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

    private let controls = SystemControlsView()

    /// Apps scroll on the left; brightness and volume stay pinned right, so
    /// they are always in the same place no matter how many apps are open.
    private lazy var container: NSView = {
        let container = NSView()

        let separator = NSBox()
        separator.boxType = .separator

        for subview in [scrollView, separator, controls] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(subview)
        }

        // Controls keep their intrinsic width; the dock takes what is left.
        controls.setContentHuggingPriority(.required, for: .horizontal)
        controls.setContentCompressionResistancePriority(.required, for: .horizontal)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            separator.leadingAnchor.constraint(equalTo: scrollView.trailingAnchor,
                                               constant: Metrics.separatorInset),
            separator.widthAnchor.constraint(equalToConstant: 1),
            separator.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            separator.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),

            controls.leadingAnchor.constraint(equalTo: separator.trailingAnchor,
                                              constant: Metrics.separatorInset),
            controls.trailingAnchor.constraint(equalTo: container.trailingAnchor,
                                               constant: -Metrics.separatorInset),
            controls.topAnchor.constraint(equalTo: container.topAnchor),
            controls.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return container
    }()

    var view: NSView { container }

    /// Parallel to the tiles in `stack`: index i's button acts on entries[i].
    private var entries: [DockEntry] = []
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

        // Rearranging the real Dock should rearrange ours.
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(reload),
            name: NSNotification.Name("com.apple.dock.prefchanged"),
            object: nil
        )

        reload()
        // Volume can have changed from the keyboard while we were off screen.
        controls.refresh()
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }

    // MARK: - Contents

    @objc private func reload() {
        entries = DockModel.entries()

        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        for (index, entry) in entries.enumerated() {
            stack.addArrangedSubview(makeTile(for: entry, at: index))
        }
    }

    private func makeTile(for entry: DockEntry, at index: Int) -> NSView {
        let button = NSButton(title: "", target: self, action: #selector(buttonTapped(_:)))
        button.tag = index
        button.bezelStyle = .inline
        button.isBordered = false
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = entry.name

        button.image = Self.barIcon(for: entry.icon)

        // Not-running apps are dimmed, as are hidden ones — same cue the
        // real Dock gives with its running dot.
        let isHidden = entry.runningApplication?.isHidden ?? false
        button.alphaValue = entry.isRunning ? (isHidden ? 0.5 : 1.0) : 0.55

        if entry.runningApplication?.isActive == true {
            button.wantsLayer = true
            button.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.2).cgColor
            button.layer?.cornerRadius = Metrics.cornerRadius
        }

        // Quitting something that is not running makes no sense.
        if entry.isRunning {
            let hold = NSPressGestureRecognizer(target: self, action: #selector(buttonHeld(_:)))
            hold.minimumPressDuration = Metrics.holdToQuit
            hold.allowedTouchTypes = [.direct]
            button.addGestureRecognizer(hold)
        }

        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: Metrics.buttonWidth).isActive = true

        return button
    }

    /// Rasterises an app icon for the bar, at 2x where that works.
    ///
    /// Some icons render only at 1x — Notes on macOS 27 is one: drawn into a
    /// 56px bitmap it comes out completely empty, while 28px is fine. The bar
    /// is a 2x panel, so those apps showed up as blank gaps. Draw at 2x,
    /// check we actually got pixels, and drop to 1x when we did not.
    private static func barIcon(for icon: NSImage) -> NSImage? {
        let points = Int(Metrics.iconSize)
        for scale in [2, 1] {
            if let image = rasterised(icon, points: points, scale: scale) { return image }
        }
        // Better a shared image resized than an empty slot.
        let fallback = icon.copy() as? NSImage
        fallback?.size = NSSize(width: points, height: points)
        return fallback
    }

    /// Returns nil when the draw produced nothing, which is how a failed
    /// icon announces itself — no error, just an empty bitmap.
    private static func rasterised(_ icon: NSImage, points: Int, scale: Int) -> NSImage? {
        let pixels = points * scale

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        icon.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.bitmapData else { return nil }
        var opaque = 0
        for y in 0..<pixels {
            for x in 0..<pixels where data[y * rep.bytesPerRow + x * rep.samplesPerPixel + 3] > 12 {
                opaque += 1
            }
        }
        guard opaque > 0 else { return nil }

        rep.size = NSSize(width: points, height: points)
        let image = NSImage(size: NSSize(width: points, height: points))
        image.addRepresentation(rep)
        return image
    }

    // MARK: - Actions

    /// Same as clicking the real Dock: bring the app to the front, or launch
    /// it if it is not running. Notably it does not hide an app that is
    /// already frontmost — the Dock does not do that either.
    @objc private func buttonTapped(_ sender: NSButton) {
        guard let entry = entry(at: sender.tag) else { return }
        Haptics.tap()

        entry.runningApplication?.unhide()

        // Always go through openApplication, even when the app is already
        // running: that sends the reopen event, which is what makes an app
        // with no windows open one. Plain activate() just focuses an app
        // that has nothing on screen.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: entry.url, configuration: configuration) { _, error in
            if let error {
                NSLog("[TouchMyBar] could not open %@: %@",
                      entry.url.lastPathComponent, error.localizedDescription)
            }
        }
    }

    @objc private func buttonHeld(_ gesture: NSPressGestureRecognizer) {
        guard gesture.state == .began,
              let button = gesture.view as? NSButton,
              let app = entry(at: button.tag)?.runningApplication else { return }

        app.terminate()
    }

    /// The list is rebuilt on every workspace event, so a tag captured when
    /// the button was made can be stale by the time it fires.
    private func entry(at index: Int) -> DockEntry? {
        guard entries.indices.contains(index) else { return nil }
        return entries[index]
    }
}
