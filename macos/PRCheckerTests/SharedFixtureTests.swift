import Foundation
import Testing
@testable import PR_Checker

/// Runs the cases in shared/fixtures, which the Windows tests check too.
@MainActor
struct SharedFixtureTests {
    private func fixture(_ name: String) throws -> [String: Any] {
        let url = try #require(Bundle(for: MemoryTokenStore.self)
            .url(forResource: name, withExtension: "json", subdirectory: "fixtures"))
        return try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func decode<T: Decodable>(_ type: T.Type, from object: Any) throws -> T {
        try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: object))
    }

    @Test func reviewList() throws {
        let data = try fixture("review-list")
        let server = try ServerAddress(parsing: try #require(data["server"] as? String))
        let user = try #require(data["user"] as? String)
        let page = try decode(Page<PullRequest>.self, from: try #require(data["dashboard"]))
        let expected = try #require(data["expected"] as? [[String: Any]])

        let items = page.values.compactMap { PRItem(reviewing: $0, as: user, server: server) }
        #expect(items.map(\.id) == expected.map { $0["id"] as? String })
        for (item, want) in zip(items, expected) {
            #expect(item.url.absoluteString == want["link"] as? String)
            #expect(item.hasNewCommits == want["newCommits"] as? Bool)
            #expect(item.hasConflicts == want["conflicts"] as? Bool)
            #expect(item.commentCount == want["comments"] as? Int)
            #expect(item.openTaskCount == want["openTasks"] as? Int)
        }
    }

    @Test func commentsByOthers() throws {
        let data = try fixture("activities")
        let page = try decode(Page<Activity>.self, from: try #require(data["page"]))
        let comments = BitbucketClient.commentsByOthers(in: page.values, excluding: try #require(data["user"] as? String))
        let expected = try #require(data["expected"] as? [[String: Any]])

        #expect(comments.map(\.id) == expected.map { $0["id"] as? Int })
        #expect(comments.map(\.created) == expected.map { ($0["created"] as? NSNumber)?.int64Value })
        #expect(comments.map(\.author) == expected.map { $0["author"] as? String })
    }

    @Test func buildStates() throws {
        let cases = try #require(try fixture("build-stats")["cases"] as? [[String: Any]])
        for testCase in cases {
            let stats = try decode(BuildStats.self, from: try #require(testCase["stats"]))
            #expect(BuildState(stats).rawValue == testCase["expected"] as? String)
        }
    }

    @Test func serverAddresses() throws {
        let data = try fixture("servers")
        for testCase in try #require(data["parse"] as? [[String: Any]]) {
            let input = try #require(testCase["input"] as? String)
            if let id = testCase["id"] as? String {
                #expect(try ServerAddress(parsing: input).id == id, "\(input)")
            } else {
                let problem = try #require(testCase["error"] as? String)
                #expect(throws: (any Error).self, "\(input)") { try ServerAddress(parsing: input) }
                do { _ = try ServerAddress(parsing: input) } catch {
                    #expect(String(describing: error) == problem, "\(input)")
                }
            }
        }
        let owns = try #require(data["owns"] as? [String: Any])
        let server = try ServerAddress(parsing: try #require(owns["server"] as? String))
        for testCase in try #require(owns["cases"] as? [[String: Any]]) {
            let url = try #require(testCase["url"] as? String)
            #expect(server.owns(URL(string: url)) == testCase["owned"] as? Bool, "\(url)")
        }
    }
}
