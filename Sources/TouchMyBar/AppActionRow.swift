import AppKit

/// What a long press on a dock tile opens: the actions for that one app.
///
/// Long press used to quit immediately. A 0.6s hold is easy to do by
/// accident with a hand resting on the bar, and losing an editor full of
/// unsaved work to a lean is not a reasonable price for a shortcut — so
/// the gesture now opens this, and quitting takes a second deliberate tap.
final class AppActionRow: NSView {

    private enum Metrics {
        static let iconSize: CGFloat = 24
        static let buttonHeight: CGFloat = 26
        static let spacing: CGFloat = 10
        static let fontSize: CGFloat = 13
        /// Long enough to read and act on, short enough that an accidental
        /// hold does not leave the dock hidden.
        static let timeout: TimeInterval = 5
    }

    enum Action {
        case quit, hide, newWindow
    }

    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let hideButton: NSButton
    private var timeoutWork: DispatchWorkItem?

    private var entry: DockEntry?
    private var onAction: ((Action, DockEntry) -> Void)?
    private var onDismiss: (() -> Void)?

    override init(frame frameRect: NSRect) {
        hideButton = Self.makeButton("Hide")
        super.init(frame: frameRect)
        build()
    }

    required init?(coder: NSCoder) {
        hideButton = Self.makeButton("Hide")
        super.init(coder: coder)
        build()
    }

    deinit { timeoutWork?.cancel() }

    // MARK: - Presenting

    func present(_ entry: DockEntry,
                 onAction: @escaping (Action, DockEntry) -> Void,
                 onDismiss: @escaping () -> Void) {
        self.entry = entry
        self.onAction = onAction
        self.onDismiss = onDismiss

        iconView.image = entry.icon
        nameLabel.stringValue = entry.name

        // Hiding something that is already hidden does nothing useful.
        hideButton.isEnabled = entry.runningApplication?.isHidden == false

        timeoutWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        timeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Metrics.timeout, execute: work)
    }

    func cancelTimeout() {
        timeoutWork?.cancel()
        timeoutWork = nil
    }

    // MARK: - Layout

    private func build() {
        iconView.imageScaling = .scaleProportionallyDown

        nameLabel.font = .systemFont(ofSize: Metrics.fontSize, weight: .semibold)
        nameLabel.lineBreakMode = .byTruncatingTail

        let quit = Self.makeButton("Quit")
        quit.target = self
        quit.action = #selector(quitTapped)
        // The destructive one, marked as such.
        quit.contentTintColor = .systemRed

        hideButton.target = self
        hideButton.action = #selector(hideTapped)

        let newWindow = Self.makeButton("New Window")
        newWindow.target = self
        newWindow.action = #selector(newWindowTapped)

        let back = Self.makeButton("Back")
        back.target = self
        back.action = #selector(backTapped)

        let row = NSStackView(views: [iconView, nameLabel, quit, hideButton, newWindow, back])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = Metrics.spacing
        row.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)

        // The name yields first when the row is tight; the buttons must
        // stay readable or they cannot be hit with any confidence.
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: Metrics.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: Metrics.iconSize),

            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private static func makeButton(_ title: String) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: Metrics.fontSize, weight: .medium)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: Metrics.buttonHeight).isActive = true
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }

    // MARK: - Actions

    @objc private func quitTapped() { fire(.quit) }
    @objc private func hideTapped() { fire(.hide) }
    @objc private func newWindowTapped() { fire(.newWindow) }
    @objc private func backTapped() { dismiss() }

    private func fire(_ action: Action) {
        Haptics.tap()
        if let entry { onAction?(action, entry) }
        dismiss()
    }

    private func dismiss() {
        cancelTimeout()
        onDismiss?()
    }
}
