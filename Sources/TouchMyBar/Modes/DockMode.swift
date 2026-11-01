import AppKit

/// The Dock as a row of icons: pinned apps whether or not they are running,
/// then anything else currently open. Tap behaves like a Dock click — launch
/// or bring to front. Press and hold a running app opens its actions.
///
/// The Dock shares the bar with the brightness, volume and mute controls,
/// arranged however BarLayout says.
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
        static let holdForActions: TimeInterval = 0.6
        static let separatorInset: CGFloat = 10
        /// Between two controls, with no rule to mark the break.
        static let groupGap: CGFloat = 20
        /// How much the Dock wants to be exactly as wide as its icons. Below
        /// everything else, so it is what gives way when the bar runs short
        /// — and below fitting-size compression, so the bar's fitting width
        /// stays what it was before the Dock could size itself.
        static let dockFitPriority = NSLayoutConstraint.Priority(
            NSLayoutConstraint.Priority.fittingSizeCompression.rawValue - 1)
        /// Reading the Dock's preferences costs under 0.1ms, so checking
        /// this often is cheaper than missing a change.
        static let dockPollInterval: TimeInterval = 2
    }

    private let stack: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = Metrics.spacing
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        // Wins over the Dock's pull towards its icons' width, so the tiles
        // never spread out when something else widens the scroll view.
        stack.setHuggingPriority(.defaultHigh, for: .horizontal)
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

    private let controls = SystemControls()
    private let actionRow = AppActionRow()

    /// Bundle ids of apps we have asked to launch and not yet seen running.
    /// Their tiles pulse, because the bar cannot bounce the way the Dock does
    /// and a tap would otherwise look like it did nothing for several seconds.
    private var launching: Set<String> = []

    private let container = NSView()
    private var layoutConstraints: [NSLayoutConstraint] = []
    private var separators: [NSView] = []
    private var layoutObserver: NSObjectProtocol?

    var view: NSView { container }

    override init() {
        super.init()
        applyLayout()
        layoutObserver = NotificationCenter.default.addObserver(
            forName: BarLayout.didChange, object: nil, queue: .main
        ) { [weak self] _ in
            self?.applyLayout()
        }
    }

    deinit {
        if let layoutObserver {
            NotificationCenter.default.removeObserver(layoutObserver)
        }
    }

    /// Parallel to the tiles in `stack`: index i's button acts on entries[i].
    private var entries: [DockEntry] = []
    private var isActive = false

    /// Last seen shape of the real Dock, to spot reordering and additions.
    private var dockSignature = ""
    private var dockPollTimer: Timer?

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

        // Rearranging the real Dock should rearrange ours. This
        // notification does not appear to fire on macOS 27, so it is a
        // fast path rather than the mechanism; the poll below is what
        // actually catches changes.
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(reload),
            name: NSNotification.Name("com.apple.dock.prefchanged"),
            object: nil
        )

        startPollingDock()
        reload()
        // Volume can have changed from the keyboard while we were off screen.
        controls.refresh()
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        dockPollTimer?.invalidate()
        dockPollTimer = nil
    }

    /// Nothing reliably announces a Dock rearrangement, so watch for one.
    /// Only a changed signature causes a rebuild — the common case is a
    /// sub-millisecond read and nothing else.
    private func startPollingDock() {
        dockPollTimer?.invalidate()

        let timer = Timer(timeInterval: Metrics.dockPollInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            let signature = DockModel.signature()
            guard signature != self.dockSignature else { return }
            self.dockSignature = signature
            self.reload()
        }
        RunLoop.main.add(timer, forMode: .common)
        dockPollTimer = timer
    }

    // MARK: - Layout

    /// Arranges the bar per BarLayout.current: left sections packed from the
    /// left edge, right ones from the right, the gap between them flexible.
    ///
    /// The Dock sizes to its icons rather than filling the bar, which is
    /// what lets it sit on either side; it only starts to scroll once the
    /// controls and the gap have nothing left to give.
    private func applyLayout() {
        // The action row is pinned to the Dock, which is about to move.
        hideActions()

        NSLayoutConstraint.deactivate(layoutConstraints)
        layoutConstraints = []
        separators = []
        container.subviews.forEach { $0.removeFromSuperview() }

        let layout = BarLayout.current
        var left = withSeparators(views(for: layout.left))
        var right = withSeparators(views(for: layout.right))

        // Across the gap the rule stays with the control rather than the
        // Dock, so it marks where the controls begin instead of floating
        // halfway along the bar.
        if let last = left.last, let first = right.first {
            if last === scrollView {
                right.insert(makeSeparator(), at: 0)
            } else if first === scrollView {
                left.append(makeSeparator())
            }
        }

        var constraints: [NSLayoutConstraint] = [
            scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor)
                .withPriority(Metrics.dockFitPriority),
        ]

        for view in left + right {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)

            if isSeparator(view) {
                constraints += [
                    view.widthAnchor.constraint(equalToConstant: 1),
                    view.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
                    view.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
                ]
            } else if view === scrollView {
                constraints += [
                    view.topAnchor.constraint(equalTo: container.topAnchor),
                    view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                ]
            } else {
                constraints.append(view.centerYAnchor.constraint(equalTo: container.centerYAnchor))
            }
        }

        // Left side, leading edge first.
        for (index, view) in left.enumerated() {
            if index == 0 {
                constraints.append(view.leadingAnchor.constraint(
                    equalTo: container.leadingAnchor, constant: edgeInset(view)))
            } else {
                let previous = left[index - 1]
                constraints.append(view.leadingAnchor.constraint(
                    equalTo: previous.trailingAnchor, constant: gap(previous, view)))
            }
        }

        // Right side, trailing edge first.
        for (index, view) in right.enumerated().reversed() {
            if index == right.count - 1 {
                constraints.append(view.trailingAnchor.constraint(
                    equalTo: container.trailingAnchor, constant: -edgeInset(view)))
            } else {
                let next = right[index + 1]
                constraints.append(view.trailingAnchor.constraint(
                    equalTo: next.leadingAnchor, constant: -gap(view, next)))
            }
        }

        // The flexible space. With one side empty it is the far edge that
        // stops the other side running off the bar.
        switch (left.last, right.first) {
        case let (last?, first?):
            constraints.append(first.leadingAnchor.constraint(
                greaterThanOrEqualTo: last.trailingAnchor, constant: gap(last, first)))
        case let (last?, nil):
            constraints.append(last.trailingAnchor.constraint(
                lessThanOrEqualTo: container.trailingAnchor, constant: -edgeInset(last)))
        case let (nil, first?):
            constraints.append(first.leadingAnchor.constraint(
                greaterThanOrEqualTo: container.leadingAnchor, constant: edgeInset(first)))
        case (nil, nil):
            break
        }

        NSLayoutConstraint.activate(constraints)
        layoutConstraints = constraints
    }

    private func views(for sections: [BarLayout.Section]) -> [NSView] {
        sections.compactMap { $0 == .dock ? scrollView : controls.view(for: $0) }
    }

    /// A rule between the Dock and any control beside it, as the bar has
    /// always had. Controls next to each other are told apart by a gap.
    private func withSeparators(_ views: [NSView]) -> [NSView] {
        var result: [NSView] = []
        for view in views {
            if let previous = result.last, previous === scrollView || view === scrollView {
                result.append(makeSeparator())
            }
            result.append(view)
        }
        return result
    }

    private func makeSeparator() -> NSView {
        let separator = NSBox()
        separator.boxType = .separator
        separators.append(separator)
        return separator
    }

    private func isSeparator(_ view: NSView) -> Bool {
        separators.contains { $0 === view }
    }

    private func gap(_ a: NSView, _ b: NSView) -> CGFloat {
        isSeparator(a) || isSeparator(b) ? Metrics.separatorInset : Metrics.groupGap
    }

    /// The Dock's tiles carry their own inset; controls need one added.
    private func edgeInset(_ view: NSView) -> CGFloat {
        view === scrollView ? 0 : Metrics.separatorInset
    }

    // MARK: - Contents

    @objc private func reload() {
        entries = DockModel.entries()
        dockSignature = DockModel.signature()

        // Anything that made it to running is no longer launching.
        launching = launching.filter { identifier in
            !entries.contains { $0.bundleIdentifier == identifier && $0.isRunning }
        }

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

        if let identifier = entry.bundleIdentifier, launching.contains(identifier) {
            addLaunchPulse(to: button)
        }

        if entry.runningApplication?.isActive == true {
            button.wantsLayer = true
            button.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.2).cgColor
            button.layer?.cornerRadius = Metrics.cornerRadius
        }

        // Quit and Hide are meaningless for an app that is not running.
        if entry.isRunning {
            let hold = NSPressGestureRecognizer(target: self, action: #selector(buttonHeld(_:)))
            hold.minimumPressDuration = Metrics.holdForActions
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

    /// Breathes the tile while its app starts up. The Dock bounces; the bar
    /// has no room for that, so it fades instead.
    private func addLaunchPulse(to button: NSButton) {
        button.wantsLayer = true
        button.alphaValue = 1

        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.3
        pulse.duration = 0.55
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        button.layer?.add(pulse, forKey: "launchPulse")
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
        if !entry.isRunning, let identifier = entry.bundleIdentifier {
            launching.insert(identifier)
            reload()
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: entry.url, configuration: configuration) { [weak self] _, error in
            guard let error else { return }
            NSLog("[TouchMyBar] could not open %@: %@",
                  entry.url.lastPathComponent, error.localizedDescription)
            // A launch that failed will never arrive, so stop waiting for it.
            DispatchQueue.main.async {
                guard let self, let identifier = entry.bundleIdentifier else { return }
                self.launching.remove(identifier)
                self.reload()
            }
        }
    }

    @objc private func buttonHeld(_ gesture: NSPressGestureRecognizer) {
        guard gesture.state == .began,
              let button = gesture.view as? NSButton,
              let entry = entry(at: button.tag) else { return }

        Haptics.tap()
        showActions(for: entry)
    }

    // MARK: - Per-app actions

    private func showActions(for entry: DockEntry) {
        actionRow.present(entry) { [weak self] action, entry in
            self?.perform(action, on: entry)
        } onDismiss: { [weak self] in
            self?.hideActions()
        }

        // Added only while shown. A hidden NSView still takes part in Auto
        // Layout — unlike an arranged subview of a stack — and this row's
        // buttons resist compression, so leaving it in the hierarchy stole
        // width from the controls and left a gap at the right of the bar.
        //
        // Pinned to the Dock, whose width is only a preference: the row
        // widens it into the flexible space when the Dock is short of
        // apps, and narrows back when it goes.
        actionRow.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(actionRow)
        NSLayoutConstraint.activate([
            actionRow.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            actionRow.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            actionRow.topAnchor.constraint(equalTo: scrollView.topAnchor),
            actionRow.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
        ])

        scrollView.isHidden = true
    }

    private func hideActions() {
        actionRow.cancelTimeout()
        // Removing it takes its constraints with it.
        actionRow.removeFromSuperview()
        scrollView.isHidden = false
    }

    private func perform(_ action: AppActionRow.Action, on entry: DockEntry) {
        switch action {
        case .quit:
            entry.runningApplication?.terminate()
        case .hide:
            entry.runningApplication?.hide()
        case .newWindow:
            // Reopening an app that already has windows is how macOS asks
            // for another one.
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.createsNewApplicationInstance = false
            NSWorkspace.shared.openApplication(at: entry.url, configuration: configuration)
        }
    }

    /// The list is rebuilt on every workspace event, so a tag captured when
    /// the button was made can be stale by the time it fires.
    private func entry(at index: Int) -> DockEntry? {
        guard entries.indices.contains(index) else { return nil }
        return entries[index]
    }
}

private extension NSLayoutConstraint {
    func withPriority(_ priority: NSLayoutConstraint.Priority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}
