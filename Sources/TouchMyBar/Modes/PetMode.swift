import AppKit

/// A small creature that paces along the bar. Exists mostly to prove the
/// mode seam holds for animated content as well as static controls: it
/// drives its own timer and gives it back on deactivate.
final class PetMode: NSObject, BarMode {

    static let identifier = "pet"
    let title = "Pet"

    private enum Metrics {
        static let frameRate: TimeInterval = 1.0 / 30.0
        static let speed: CGFloat = 1.4      // points per frame
        static let size: CGFloat = 26
        static let hopHeight: CGFloat = 4
    }

    private let canvas = PetCanvas()
    var view: NSView { canvas }

    private var timer: Timer?

    func activate() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Metrics.frameRate, repeats: true) { [weak self] _ in
            self?.canvas.step()
        }
        // .common so the animation survives tracking loops elsewhere in the UI.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func deactivate() {
        timer?.invalidate()
        timer = nil
    }

    private final class PetCanvas: NSView {
        private var x: CGFloat = 0
        private var direction: CGFloat = 1
        private var frameCount = 0

        override var isFlipped: Bool { true }

        func step() {
            frameCount += 1

            x += Metrics.speed * direction
            if x <= 0 {
                x = 0
                direction = 1
            } else if x >= bounds.width - Metrics.size {
                x = max(0, bounds.width - Metrics.size)
                direction = -1
            }

            needsDisplay = true
        }

        override func draw(_ dirtyRect: NSRect) {
            NSColor.clear.setFill()
            dirtyRect.fill()

            // A two-frame hop, so the walk reads as movement rather than a slide.
            let hop = (frameCount / 6) % 2 == 0 ? Metrics.hopHeight : 0
            let y = (bounds.height - Metrics.size) / 2 + hop

            let body = NSRect(x: x, y: y, width: Metrics.size, height: Metrics.size)
            NSColor.systemTeal.setFill()
            NSBezierPath(ovalIn: body).fill()

            // Eye on the leading edge, so it looks where it is going.
            let eyeX = direction > 0 ? body.maxX - 9 : body.minX + 5
            let eye = NSRect(x: eyeX, y: body.minY + 7, width: 4, height: 4)
            NSColor.black.setFill()
            NSBezierPath(ovalIn: eye).fill()
        }
    }
}
