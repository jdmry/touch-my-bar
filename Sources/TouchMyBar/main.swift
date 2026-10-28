import AppKit

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate

// .accessory: menu bar item only, no Dock tile and no main menu.
application.setActivationPolicy(.accessory)
application.run()
