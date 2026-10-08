import Foundation

/// Runs a user-configured command when a PR enters the review list or gets new commits,
/// e.g. to start an automated pre-check. The command is split into arguments once and
/// placeholders are filled into each argument, so PR content never passes through a shell.
enum Automation {
    static let placeholders = ["link", "commit", "project", "repo", "id", "source", "target", "title", "author"]

    enum TemplateError: LocalizedError, Equatable {
        case empty, unterminatedQuote

        var errorDescription: String? {
            switch self {
            case .empty: "Enter a command."
            case .unterminatedQuote: "The command has an unterminated quote."
            }
        }
    }

    /// Splits like a shell (whitespace, '…', "…", backslash escapes) without any expansion,
    /// then fills placeholders per argument and expands a leading "~/".
    static func arguments(for template: String, item: PRItem) throws -> [String] {
        let values: [String: String] = [
            "link": item.url.absoluteString, "commit": item.latestCommit,
            "project": item.projectKey, "repo": item.repoSlug, "id": String(item.number),
            "source": item.sourceBranch, "target": item.targetBranch,
            "title": item.title, "author": item.authorName,
        ]
        return try split(template).map { token in
            var argument = token
            for (name, value) in values {
                argument = argument.replacingOccurrences(of: "{\(name)}", with: value)
            }
            if argument.hasPrefix("~/") {
                argument = FileManager.default.homeDirectoryForCurrentUser.path + argument.dropFirst()
            }
            return argument
        }
    }

    static func split(_ command: String) throws -> [String] {
        var tokens: [String] = []
        var current = ""
        var inToken = false
        var quote: Character?
        var escaped = false
        for character in command {
            if escaped {
                current.append(character)
                escaped = false
            } else if character == "\\" && quote != "'" {
                escaped = true
                inToken = true
            } else if let open = quote {
                if character == open { quote = nil } else { current.append(character) }
            } else if character == "'" || character == "\"" {
                quote = character
                inToken = true
            } else if character.isWhitespace {
                if inToken { tokens.append(current) }
                current = ""
                inToken = false
            } else {
                current.append(character)
                inToken = true
            }
        }
        guard quote == nil, !escaped else { throw TemplateError.unterminatedQuote }
        if inToken { tokens.append(current) }
        guard !tokens.isEmpty else { throw TemplateError.empty }
        return tokens
    }

    /// PRs whose current commit hasn't triggered the command yet, and the updated record,
    /// limited to PRs still in the list.
    static func pending(_ items: [PRItem], alreadyTriggered: Set<String>) -> (items: [PRItem], triggered: Set<String>) {
        let keys = items.map { "\($0.id)@\($0.latestCommit)" }
        let fresh = zip(items, keys).filter { !alreadyTriggered.contains($0.1) }.map(\.0)
        return (fresh, Set(keys))
    }

    nonisolated static var logFile: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Logs/PR Checker/automation.log")
    }

    /// Starts the command for each PR without waiting; output goes to the log file.
    static func run(_ template: String, for items: [PRItem]) {
        for item in items {
            do {
                let arguments = try arguments(for: template, item: item)
                let process = Process()
                if arguments[0].hasPrefix("/") {
                    process.executableURL = URL(fileURLWithPath: arguments[0])
                    process.arguments = Array(arguments.dropFirst())
                } else {
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                    process.arguments = arguments
                }
                var environment = ProcessInfo.processInfo.environment
                environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
                process.environment = environment
                let log = try openLog()
                process.standardOutput = log
                process.standardError = log
                let id = item.id
                write("\(Date.now.ISO8601Format()) \(id) @ \(item.latestCommit.prefix(10)): starting \(arguments[0])\n")
                process.terminationHandler = { finished in
                    write("\(Date.now.ISO8601Format()) \(id): exited \(finished.terminationStatus)\n")
                }
                try process.run()
            } catch {
                write("\(Date.now.ISO8601Format()) \(item.id): couldn't start: \(error.localizedDescription)\n")
            }
        }
    }

    private static func openLog() throws -> FileHandle {
        let directory = logFile.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: logFile.path) {
            FileManager.default.createFile(atPath: logFile.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: logFile)
        try handle.seekToEnd()
        return handle
    }

    nonisolated private static func write(_ line: String) {
        guard let handle = try? FileHandle(forWritingTo: logFile) else { return }
        _ = try? handle.seekToEnd()
        handle.write(Data(line.utf8))
        try? handle.close()
    }
}
