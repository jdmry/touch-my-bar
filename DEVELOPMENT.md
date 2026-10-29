# Development notes

How Touch My Bar is built, and what it leans on. For using the app, see
the [README](README.md).

## Build

```bash
./Scripts/make-app.sh          # or: ./Scripts/make-app.sh release
open "build/Touch My Bar.app"
```

Debug builds are native for speed; release builds are universal.

`Scripts/release.sh <version>` builds a release, packages a DMG, and
rewrites the version and sha256 in the Homebrew cask next door.

## Adding a mode

Conform to `BarMode` and add an instance to `modes` in `AppDelegate`:

```swift
final class MyMode: NSObject, BarMode {
    static let identifier = "mine"
    let title = "My Mode"
    var view: NSView { myView }

    func activate()   { /* start timers and observers */ }
    func deactivate() { /* stop them */ }
}
```

`activate`/`deactivate` bracket the time a mode is actually on the bar, so an
inactive mode costs nothing. The mode list only appears in the menu once
there is more than one.

## About the private APIs

Owning the Touch Bar across every app is not something the public SDK allows,
and neither are several of the things on it.

| Symbol | Framework | For |
| --- | --- | --- |
| `+[NSTouchBar presentSystemModalTouchBar:placement:systemTrayItemIdentifier:]` | AppKit | Owning the bar |
| `+[NSTouchBar dismissSystemModalTouchBar:]` | AppKit | Releasing it |
| `+[NSTouchBarItem addSystemTrayItem:]` | AppKit | Control Strip icon |
| `DFRElementSetControlStripPresenceForIdentifier` | DFRFoundation | Showing that icon |
| `DFRSystemModalShowsCloseBoxWhenFrontMost` | DFRFoundation | Suppressing the close box |
| `DisplayServicesGet/SetBrightness` | DisplayServices | Brightness |
| `MTActuatorCreateFromDeviceID` / `Open` / `Actuate` | MultitouchSupport | Haptics |

All verified present on macOS 27. The Touch Bar symbols are
checked at runtime via `TouchBarController.isSupported`, brightness and
haptics are resolved with `dlsym` and degrade to disabled buttons rather than
a crash. Consequences: not App Store distributable, and any macOS update can
break it.

Volume deliberately uses public CoreAudio rather than synthesised media keys,
which would require an Accessibility grant.

## Things that did not work

**The system HUD.** `OSDManager` in OSD.framework is the real thing behind
the brightness and volume overlays, and the call matches its signature
exactly, but on macOS 27 it does nothing from an unprivileged process —
`OSDUIHelper` is never even launched. The HUD here is drawn by the app.

**Now Playing.** `MediaRemote` exports everything needed, but the
now-playing info is entitlement-gated and comes back empty.

**Haptics on the bar itself.** There is no actuator behind the Touch Bar; the
only Taptic Engine is under the trackpad, so a tap is felt in the palm rest.
The actuator accepts pattern ids 1-6, 15 and 16 — 15 and 16 return success
while being too faint to notice — and nothing lands harder than 6, which is
why there are two strength settings rather than three.

**Notes' icon.** It renders at 1x and returns an empty bitmap at 2x, so its
tile came out blank on a 2x panel. Of the apps checked it is the
only one, but the fallback in `DockMode.barIcon(for:)` is general: draw at
2x, check for pixels, drop to 1x if there are none.

## Ideas not built yet

- Audio output switcher next to the volume keys
- Context-aware bar: different controls per frontmost app
- Quotes, clipboard history, user-defined shortcut buttons
- System stats, next calendar event
