import ServiceManagement

/// Start at login, through SMAppService.
///
/// The registration is the system's, not a preference of ours: asking
/// SMAppService for its status is the only honest source, since the user
/// can revoke it in System Settings > General > Login Items without the
/// app hearing about it.
enum LoginItem {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns the state it settled on; on failure that is the old one.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("[TouchMyBar] could not %@ login item: %@",
                  enabled ? "register" : "unregister", error.localizedDescription)
        }
        return isEnabled
    }
}
