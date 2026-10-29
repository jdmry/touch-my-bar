import AppKit

/// The on-screen overlay for brightness and volume changes.
///
/// macOS has its own HUD behind OSDManager in OSD.framework, and the call
/// matches its signature exactly, but on macOS 27 it does nothing from an
/// unprivileged process — OSDUIHelper is never even launched. So this draws
/// its own, shaped like the current macOS one: a small translucent pill
/// tucked under the menu bar at the top right, icon beside a slim track,
/// fading out after a moment.
@MainActor
enum SystemHUD {

    private static let segments = 16

    static func showBrightness(_ level: Float) {
        show(symbol: "sun.max.fill", level: level)
    }

    static func showVolume(_ level: Float, muted: Bool) {
        show(symbol: muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
             level: muted ? 0 : level)
    }

    private static func show(symbol: String, level: Float) {
        let filled = Int((level * Float(segments)).rounded())
        panel.present(symbol: symbol, filled: min(max(filled, 0), segments), of: segments)
    }

    private static let panel = HUDPanel()
}

/// A borderless, non-activating panel. It must never take focus: the point
/// is to confirm a change without interrupting whatever is in front.
@MainActor
private final class HUDPanel {

    private enum Metrics {
        static let width: CGFloat = 180
        static let height: CGFloat = 44
        static let edgeMargin: CGFloat = 12
        static let cornerRadius: CGFloat = 14
        static let visibleFor: TimeInterval = 0.9
        static let fadeOut: TimeInterval = 0.3
    }

    private let window: NSPanel
    private let content = HUDContentView()
    private var hideWorkItem: DispatchWorkItem?

    init() {
        window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Metrics.width, height: Metrics.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false

        // System material rather than a flat fill, so it sits on whatever is
        // behind it the way the real HUD does.
        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = Metrics.cornerRadius
        blur.layer?.cornerCurve = .continuous
        blur.layer?.masksToBounds = true

        content.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            content.topAnchor.constraint(equalTo: blur.topAnchor),
            content.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
        ])

        window.contentView = blur
    }

    func present(symbol: String, filled: Int, of total: Int) {
        content.update(symbol: symbol, filled: filled, total: total)
        reposition()

        hideWorkItem?.cancel()

        window.animator().alphaValue = 1
        window.alphaValue = 1
        window.orderFrontRegardless()

        let hide = DispatchWorkItem { [weak self] in self?.fadeOut() }
        hideWorkItem = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + Metrics.visibleFor, execute: hide)
    }

    private func fadeOut() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Metrics.fadeOut
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.window.orderOut(nil)
        }
    }

    /// Top right, just under the menu bar — `visibleFrame` already excludes
    /// the menu bar, so its top edge is the right anchor.
    private func reposition() {
        guard let screen = NSScreen.main else { return }
        let area = screen.visibleFrame
        window.setFrame(
            NSRect(x: area.maxX - Metrics.width - Metrics.edgeMargin,
                   y: area.maxY - Metrics.height - Metrics.edgeMargin,
                   width: Metrics.width,
                   height: Metrics.height),
            display: false
        )
    }
}

@MainActor
private final class HUDContentView: NSView {

    private enum Metrics {
        static let symbolSize: CGFloat = 17
        static let iconColumn: CGFloat = 40
        static let trackHeight: CGFloat = 5
        static let trailingInset: CGFloat = 16
    }

    private var symbolName = "sun.max.fill"
    private var filled = 0
    private var total = 16

    func update(symbol: String, filled: Int, total: Int) {
        symbolName = symbol
        self.filled = filled
        self.total = total
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        drawSymbol()
        drawTrack()
    }

    private func drawSymbol() {
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: Metrics.symbolSize, weight: .medium))
        else { return }

        let size = image.size
        let rect = NSRect(x: (Metrics.iconColumn - size.width) / 2,
                          y: (bounds.height - size.height) / 2,
                          width: size.width, height: size.height)

        image.draw(in: rect)
        NSColor.labelColor.set()
        rect.fill(using: .sourceAtop)
    }

    /// One continuous track rather than 16 chiclets: quieter, and closer to
    /// what macOS shows now.
    private func drawTrack() {
        let x = Metrics.iconColumn
        let width = bounds.width - x - Metrics.trailingInset
        guard width > 0 else { return }

        let rect = NSRect(x: x, y: (bounds.height - Metrics.trackHeight) / 2,
                          width: width, height: Metrics.trackHeight)
        let radius = Metrics.trackHeight / 2

        NSColor.labelColor.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()

        let fraction = total > 0 ? CGFloat(filled) / CGFloat(total) : 0
        guard fraction > 0 else { return }

        // Never thinner than the cap, or the rounded end disappears.
        var fill = rect
        fill.size.width = max(Metrics.trackHeight, rect.width * fraction)
        NSColor.labelColor.setFill()
        NSBezierPath(roundedRect: fill, xRadius: radius, yRadius: radius).fill()
    }
}
