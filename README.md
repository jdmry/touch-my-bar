# Touch My Bar

A menu bar app that takes over the Touch Bar system-wide and fills it with
whatever you want — a dock, a dashboard, a pet, a game.

Built for a 13" MacBook Pro (M1, `a Touch Bar MacBook Pro`) on macOS 27.

## Status

Working skeleton:

- Control Strip icon that toggles the custom bar on and off
- A mode system — each mode is one view, activated only while on screen
- **Dock**: running apps, tap to switch or hide, press and hold to quit
- **Pet**: a creature that paces the bar (proves the seam works for animation)

## Build and run

```bash
./Scripts/make-app.sh          # or: ./Scripts/make-app.sh release
open "build/Touch My Bar.app"
```

Quit from the menu bar icon. Quitting removes the Control Strip item; force
quitting can leave it behind until the next login.

### Touch Bar settings

In System Settings → Keyboard → Touch Bar Settings, set **Touch Bar shows**
to "App Controls" and keep **Show Control Strip** on. Without the Control
Strip there is no icon to toggle the bar with (the menu bar item still works).

## Adding a mode

Conform to `BarMode`, then add an instance to `modes` in `AppDelegate`:

```swift
final class MyMode: NSObject, BarMode {
    static let identifier = "mine"
    let title = "My Mode"
    var view: NSView { myView }

    func activate()   { /* start timers and observers */ }
    func deactivate() { /* stop them */ }
}
```

`activate`/`deactivate` bracket the time the mode is actually on the bar, so
an inactive mode costs nothing.

## About the private APIs

Owning the Touch Bar across every app is not something the public SDK allows.
This app uses Apple SPI, declared in `Sources/TouchBarPrivate/include/TouchBarPrivate.h`:

| Symbol | Source |
| --- | --- |
| `+[NSTouchBar presentSystemModalTouchBar:placement:systemTrayItemIdentifier:]` | AppKit |
| `+[NSTouchBar dismissSystemModalTouchBar:]` | AppKit |
| `+[NSTouchBarItem addSystemTrayItem:]` | AppKit |
| `DFRElementSetControlStripPresenceForIdentifier` | DFRFoundation |
| `DFRSystemModalShowsCloseBoxWhenFrontMost` | DFRFoundation |

Consequences:

- **Not App Store distributable.** Private API use is an automatic rejection.
- **Can break on any macOS update.** All six symbols were verified present on
  macOS 27. `TouchBarController.isSupported` checks for them
  at runtime, so a future removal shows an alert instead of crashing.
- The build links `/System/Library/PrivateFrameworks` explicitly via
  `unsafeFlags` in `Package.swift`.

## Ideas not built yet

- Context-aware bar: different controls per frontmost app
- System stats, now playing, calendar
- Audio visualiser, typing ripples
- One-lane games — the bar's shape suits them
