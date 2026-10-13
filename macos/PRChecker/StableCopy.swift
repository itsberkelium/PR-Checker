import AppKit
import Security

/// A copy of the stable app, kept while on the dev channel. Sparkle refuses to install an older
/// version, so going back from a dev build to the stable one restores this copy instead.
struct StableCopy {
    /// Only an app signed with PR Checker's Developer ID is put back.
    nonisolated static let requirement =
        #"anchor apple generic and identifier "dev.berke.PRChecker" and certificate leaf[subject.OU] = "L4U4H3GS68""#

    /// e.g. ~/Library/Application Support/dev.berke.PRChecker/Stable/PR Checker.app
    let url: URL
    var verify: (URL) throws -> Void = StableCopy.verifySignature

    static let standard = StableCopy(url: URL.applicationSupportDirectory
        .appending(path: Bundle.main.bundleIdentifier ?? "dev.berke.PRChecker")
        .appending(path: "Stable")
        .appending(path: Bundle.main.bundleURL.lastPathComponent))

    /// Dev builds are versioned like 0.3.0d1 (package.sh --publish-dev).
    static func isDevBuild(_ version: String) -> Bool {
        version.range(of: #"^\d+\.\d+\.\d+d\d+$"#, options: .regularExpression) != nil
    }

    static var runningVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    /// The kept copy's version, or nil when there's none. Read from the file each time:
    /// `Bundle` caches it per path, and the copy can be replaced.
    var version: String? {
        Self.version(of: url)
    }

    static func version(of app: URL) -> String? {
        let plist = NSDictionary(contentsOf: app.appending(path: "Contents/Info.plist"))
        return plist?["CFBundleShortVersionString"] as? String
    }

    /// Keeps a copy of `app` when it's a stable build. A dev build keeps the copy already there,
    /// since that's still the stable version to go back to.
    func keep(_ app: URL, version: String) throws {
        guard !Self.isDevBuild(version) else { return }
        let files = FileManager.default
        try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if files.fileExists(atPath: url.path) { try files.removeItem(at: url) }
        try files.copyItem(at: app, to: url)
    }

    /// Removes the copy; nothing to go back to once the stable version is running again.
    func discard() {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    /// Checks the copy's signature, then moves it over `app`. The copy is used up.
    func restore(over app: URL) throws {
        try verify(url)
        _ = try FileManager.default.replaceItemAt(app, withItemAt: url)
        discard()
    }

    /// Throws the Security framework's error, whose message macOS localizes.
    nonisolated static func verifySignature(_ app: URL) throws {
        func check(_ status: OSStatus) throws {
            guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        }
        var code: SecStaticCode?
        var requirement: SecRequirement?
        try check(SecStaticCodeCreateWithPath(app as CFURL, [], &code))
        try check(SecRequirementCreateWithString(Self.requirement as CFString, [], &requirement))
        guard let code else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(errSecCSUnsigned)) }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        try check(SecStaticCodeCheckValidity(code, flags, requirement))
    }

    /// Opens `app` again once this process has quit, then quits.
    static func relaunch(_ app: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // The pid and path are arguments, never part of the script.
        process.arguments = ["-c", #"while kill -0 "$1" 2>/dev/null; do sleep 0.2; done; open "$2""#,
                             "sh", String(ProcessInfo.processInfo.processIdentifier), app.path]
        try? process.run()
        NSApp.terminate(nil)
    }
}
