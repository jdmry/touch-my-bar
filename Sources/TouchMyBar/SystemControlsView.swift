import AppKit

/// Brightness and volume keys for the right-hand end of the bar.
///
/// Repeats while held, the way the hardware keys do — one tap per step is
/// tedious when the step is 1/16.
final class SystemControlsView: NSView {

    private enum Metrics {
        static let buttonWidth: CGFloat = 68
        /// The mute button carries a word, which needs more room than a glyph.
        static let muteButtonWidth: CGFloat = 92
        static let spacing: CGFloat = 8
        static let groupGap: CGFloat = 20
        static let symbolPointSize: CGFloat = 22
        static let muteFontSize: CGFloat = 13
        static let repeatDelay: TimeInterval = 0.35
        static let repeatInterval: TimeInterval = 0.09
    }

    fileprivate enum Action {
        case brightnessDown, brightnessUp, volumeDown, volumeUp, mute
    }

    private var muteButton: NSButton?
    private var repeatTimer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        build()
    }

    deinit {
        repeatTimer?.invalidate()
    }

    /// Re-reads mute state. Call when the bar comes back on screen, since
    /// the volume can have changed from the keyboard meanwhile.
    func refresh() {
        updateMuteIcon()
    }

    // MARK: - Layout

    private func build() {
        let brightness = NSStackView(views: [
            makeButton("sun.min", .brightnessDown, "Brightness down"),
            makeButton("sun.max", .brightnessUp, "Brightness up"),
        ])
        let volume = NSStackView(views: [
            makeButton("speaker.wave.1.fill", .volumeDown, "Volume down"),
            makeButton("speaker.wave.3.fill", .volumeUp, "Volume up"),
        ])

        // A word rather than a glyph: "muted" and "will mute" look alike as
        // a crossed-out speaker, and the bar has room for the real word.
        let mute = NSButton(title: "MUTE", target: self, action: #selector(buttonTapped(_:)))
        mute.bezelStyle = .rounded
        mute.tag = Action.mute.rawTag
        mute.translatesAutoresizingMaskIntoConstraints = false
        mute.widthAnchor.constraint(equalToConstant: Metrics.muteButtonWidth).isActive = true
        muteButton = mute

        for stack in [brightness, volume] {
            stack.orientation = .horizontal
            stack.spacing = Metrics.spacing
        }

        // Brightness buttons do nothing on a machine whose panel
        // DisplayServices cannot drive; show that rather than lying.
        brightness.isHidden = !SystemBrightness.isAvailable

        let row = NSStackView(views: [brightness, volume, mute])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = Metrics.groupGap

        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        updateMuteIcon()
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

    private func perform(_ action: Action) {
        Haptics.tap()

        switch action {
        case .brightnessDown:
            SystemBrightness.decrease()
            SystemHUD.showBrightness(SystemBrightness.level)
        case .brightnessUp:
            SystemBrightness.increase()
            SystemHUD.showBrightness(SystemBrightness.level)
        case .volumeDown, .volumeUp:
            action == .volumeUp ? SystemVolume.increase() : SystemVolume.decrease()
            updateMuteIcon()
            SystemHUD.showVolume(SystemVolume.level, muted: SystemVolume.isMuted)
        case .mute:
            SystemVolume.toggleMute()
            updateMuteIcon()
            SystemHUD.showVolume(SystemVolume.level, muted: SystemVolume.isMuted)
        }
    }

    /// The label says what the button will do, not what the state is:
    /// "UNMUTE" while muted, "MUTE" while audible.
    private func updateMuteIcon() {
        guard let muteButton else { return }
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
private extension SystemControlsView.Action {
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
