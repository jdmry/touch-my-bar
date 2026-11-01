import AppKit

/// Brightness, volume and mute keys, each as its own piece of the bar so
/// the layout can put them anywhere (see BarLayout).
///
/// Repeats while held, the way the hardware keys do — one tap per step is
/// tedious when the step is 1/16.
final class SystemControls: NSObject {

    private enum Metrics {
        static let buttonWidth: CGFloat = 68
        /// The mute button carries a word, which needs more room than a glyph.
        static let muteButtonWidth: CGFloat = 92
        static let spacing: CGFloat = 8
        static let symbolPointSize: CGFloat = 22
        static let muteFontSize: CGFloat = 13
        static let repeatDelay: TimeInterval = 0.35
        static let repeatInterval: TimeInterval = 0.09
    }

    fileprivate enum Action {
        case brightnessDown, brightnessUp, volumeDown, volumeUp, mute
    }

    private lazy var brightnessView: NSView = makePair(
        makeButton("sun.min", .brightnessDown, "Brightness down"),
        makeButton("sun.max", .brightnessUp, "Brightness up")
    )

    private lazy var volumeView: NSView = makePair(
        makeButton("speaker.wave.1.fill", .volumeDown, "Volume down"),
        makeButton("speaker.wave.3.fill", .volumeUp, "Volume up")
    )

    /// A word rather than a glyph: "muted" and "will mute" look alike as a
    /// crossed-out speaker, and the bar has room for the real word.
    private lazy var muteButton: NSButton = {
        let mute = NSButton(title: "MUTE", target: self, action: #selector(buttonTapped(_:)))
        mute.bezelStyle = .rounded
        mute.tag = Action.mute.rawTag
        mute.translatesAutoresizingMaskIntoConstraints = false
        mute.widthAnchor.constraint(equalToConstant: Metrics.muteButtonWidth).isActive = true
        Self.holdShape(mute)
        return mute
    }()

    private var repeatTimer: Timer?

    override init() {
        super.init()
        updateMuteIcon()
    }

    deinit {
        repeatTimer?.invalidate()
    }

    /// The view for one section of the bar, created once and reused. Nil
    /// for sections that are not ours, and for brightness on a machine
    /// whose panel DisplayServices cannot drive — better absent than a
    /// pair of buttons that do nothing.
    func view(for section: BarLayout.Section) -> NSView? {
        switch section {
        case .dock:       return nil
        case .brightness: return SystemBrightness.isAvailable ? brightnessView : nil
        case .volume:     return volumeView
        case .mute:       return muteButton
        }
    }

    /// Re-reads mute state. Call when the bar comes back on screen, since
    /// the volume can have changed from the keyboard meanwhile.
    func refresh() {
        updateMuteIcon()
    }

    // MARK: - Layout

    private func makePair(_ first: NSButton, _ second: NSButton) -> NSView {
        let stack = NSStackView(views: [first, second])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = Metrics.spacing
        Self.holdShape(stack)
        return stack
    }

    /// Controls keep their width whatever the layout; the Dock is the
    /// part of the bar that gives way when space runs short.
    private static func holdShape(_ view: NSView) {
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    private func makeButton(_ symbol: String, _ action: Action, _ label: String) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(.init(pointSize: Metrics.symbolPointSize, weight: .regular))

        let button = NSButton(image: image ?? NSImage(), target: self, action: #selector(buttonTapped(_:)))
        button.bezelStyle = .rounded
        button.tag = action.rawTag
        button.toolTip = label
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: Metrics.buttonWidth).isActive = true

        // Hold to repeat. Mute is a toggle, so it is excluded.
        if action != .mute {
            let hold = NSPressGestureRecognizer(target: self, action: #selector(buttonHeld(_:)))
            hold.minimumPressDuration = Metrics.repeatDelay
            hold.allowedTouchTypes = [.direct]
            button.addGestureRecognizer(hold)
        }

        return button
    }

    // MARK: - Actions

    @objc private func buttonTapped(_ sender: NSButton) {
        guard let action = Action(rawTag: sender.tag) else { return }
        perform(action)
    }

    @objc private func buttonHeld(_ gesture: NSPressGestureRecognizer) {
        guard let button = gesture.view as? NSButton,
              let action = Action(rawTag: button.tag) else { return }

        switch gesture.state {
        case .began:
            startRepeating(action)
        case .ended, .cancelled, .failed:
            stopRepeating()
        default:
            break
        }
    }

    private func startRepeating(_ action: Action) {
        stopRepeating()
        let timer = Timer(timeInterval: Metrics.repeatInterval, repeats: true) { [weak self] _ in
            self?.perform(action)
        }
        RunLoop.main.add(timer, forMode: .common)
        repeatTimer = timer
    }

    private func stopRepeating() {
        repeatTimer?.invalidate()
        repeatTimer = nil
    }

    /// Every caller is a button action or a main-run-loop timer, so this is
    /// always on the main thread; the HUD just needs telling so.
    private func perform(_ action: Action) {
        Haptics.tap()

        switch action {
        case .brightnessDown, .brightnessUp:
            action == .brightnessUp ? SystemBrightness.increase() : SystemBrightness.decrease()
            let level = SystemBrightness.level
            MainActor.assumeIsolated { SystemHUD.showBrightness(level) }
        case .volumeDown, .volumeUp, .mute:
            switch action {
            case .volumeUp:   SystemVolume.increase()
            case .volumeDown: SystemVolume.decrease()
            default:          SystemVolume.toggleMute()
            }
            updateMuteIcon()
            let level = SystemVolume.level, muted = SystemVolume.isMuted
            MainActor.assumeIsolated { SystemHUD.showVolume(level, muted: muted) }
        }
    }

    /// The label says what the button will do, not what the state is:
    /// "UNMUTE" while muted, "MUTE" while audible.
    private func updateMuteIcon() {
        let muted = SystemVolume.isMuted

        muteButton.attributedTitle = NSAttributedString(
            string: muted ? "UNMUTE" : "MUTE",
            attributes: [
                .font: NSFont.systemFont(ofSize: Metrics.muteFontSize, weight: .semibold),
                .foregroundColor: muted ? NSColor.systemRed : NSColor.labelColor,
            ]
        )
        muteButton.toolTip = muted ? "Unmute" : "Mute"
    }
}

// NSButton carries an Int tag, so the action enum travels as one.
private extension SystemControls.Action {
    var rawTag: Int {
        switch self {
        case .brightnessDown: return 1
        case .brightnessUp:   return 2
        case .volumeDown:     return 3
        case .volumeUp:       return 4
        case .mute:           return 5
        }
    }

    init?(rawTag: Int) {
        switch rawTag {
        case 1: self = .brightnessDown
        case 2: self = .brightnessUp
        case 3: self = .volumeDown
        case 4: self = .volumeUp
        case 5: self = .mute
        default: return nil
        }
    }
}
