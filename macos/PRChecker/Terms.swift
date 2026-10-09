import AppKit

/// The one-time Terms of Use agreement on first launch (and after the terms change).
enum Terms {
    /// Bump when TERMS.md changes in a way users must agree to again; keep in sync with Windows.
    static let version = 1

    /// Asks until the user agrees or quits. Returns false if the app is quitting.
    static func ensureAccepted(settings: AppSettings = .shared) -> Bool {
        guard settings.acceptedTermsVersion < version else { return true }
        NSApp.activate()
        while true {
            let alert = NSAlert()
            alert.messageText = L10n.welcomeTitle
            alert.informativeText = L10n.termsPromptMac
            alert.addButton(withTitle: L10n.agree)
            alert.addButton(withTitle: L10n.viewTerms)
            alert.addButton(withTitle: L10n.quit)
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                settings.acceptedTermsVersion = version
                return true
            case .alertSecondButtonReturn:
                NSWorkspace.shared.open(Support.termsOfUse)
            default:
                NSApp.terminate(nil)
                return false
            }
        }
    }
}
