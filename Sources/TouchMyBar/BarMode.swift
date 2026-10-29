import AppKit

/// One thing the Touch Bar can become: a dock, a dashboard, a game, a pet.
///
/// A mode owns a single view that fills the bar. `activate` and `deactivate`
/// bracket the time it is on screen — start timers and observers in one,
/// tear them down in the other, so an inactive mode costs nothing.
protocol BarMode: AnyObject {
    /// Stable identifier, used to remember the last selected mode.
    static var identifier: String { get }

    /// Shown in the menu bar menu.
    var title: String { get }

    /// The view that fills the bar. Created once, reused across activations.
    var view: NSView { get }

    func activate()
    func deactivate()
}

extension BarMode {
    var identifier: String { Self.identifier }
    func activate() {}
    func deactivate() {}
}
