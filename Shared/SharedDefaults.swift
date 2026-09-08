import Foundation

/// The sliver of state the complication needs. Kept deliberately tiny: the widget
/// extension should never have to authenticate or hit the network itself.
nonisolated enum SharedDefaults {
    static let suiteName = "group.ai.redclay.craftwatch"

    private enum Key {
        static let openTaskCount = "openTaskCount"
        static let updatedAt = "openTaskCountUpdatedAt"
        static let pendingCount = "pendingCaptureCount"
        static let signOutReason = "lastSignOutReason"
    }

    private static var store: UserDefaults? { UserDefaults(suiteName: suiteName) }

    static var openTaskCount: Int? {
        get { store?.object(forKey: Key.openTaskCount) as? Int }
        set {
            guard let store else { return }
            if let newValue {
                store.set(newValue, forKey: Key.openTaskCount)
                store.set(Date(), forKey: Key.updatedAt)
            } else {
                store.removeObject(forKey: Key.openTaskCount)
            }
        }
    }

    static var updatedAt: Date? {
        store?.object(forKey: Key.updatedAt) as? Date
    }

    /// Why the app last cleared its credentials. Shown on the connect prompt so a
    /// silent sign-out is explainable rather than mysterious.
    static var lastSignOutReason: String? {
        get { store?.string(forKey: Key.signOutReason) }
        set {
            guard let store else { return }
            if let newValue {
                store.set(newValue, forKey: Key.signOutReason)
            } else {
                store.removeObject(forKey: Key.signOutReason)
            }
        }
    }

    static var pendingCount: Int {
        get { store?.integer(forKey: Key.pendingCount) ?? 0 }
        set { store?.set(newValue, forKey: Key.pendingCount) }
    }
}
