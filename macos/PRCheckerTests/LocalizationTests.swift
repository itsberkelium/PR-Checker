import Foundation
import Testing
@testable import PR_Checker

/// Uses `Localizer.$override`, which only affects each test's own task, so tests running in
/// parallel keep seeing English.
@MainActor
struct LocalizationTests {
    @Test func systemPreferenceFollowsTheMacLanguage() {
        let localizer = Localizer()
        localizer.systemLanguage = { "tr-TR" }
        #expect(localizer.resolve(.system) == .turkish)
        localizer.systemLanguage = { "de-DE" }
        #expect(localizer.resolve(.system) == .english)
        #expect(localizer.resolve(.turkish) == .turkish)
        #expect(localizer.resolve(.english) == .english)
    }

    @Test func notificationsUseTheChosenLanguage() throws {
        let before = PRItem(try makePR(myStatus: "UNAPPROVED", lastReviewed: nil, latest: "a", merge: "CLEAN"), server: testServer)
        var after = PRItem(try makePR(myStatus: "APPROVED", lastReviewed: nil, latest: "a", merge: "CONFLICTED"), server: testServer)
        after.commentsByOthers = [.init(id: 2, created: 9, author: "Ali"), .init(id: 1, created: 8, author: "Veli")]
        let old = Snapshot(toReview: [], mine: [before], previous: nil, isShown: { _ in true })
        let new = Snapshot(toReview: [], mine: [after], previous: old, isShown: { _ in true })

        let body = Localizer.$override.withValue(.turkish) {
            ChangeDetector.changes(from: old, to: new, toReview: [], mine: [after]).first?.body
        }
        #expect(body == "✅ Sam Reviewer onayladı\n⚠️ Birleştirme çakışmaları\n💬 2 yeni yorum: Veli, Ali")
    }

    @Test func errorsUseTheChosenLanguage() {
        Localizer.$override.withValue(.turkish) {
            #expect(APIError.http(502).errorDescription == "Bitbucket HTTP 502 döndürdü.")
            #expect(ServerAddress.Problem.notHTTPS.errorDescription == "Sunucu adresi https:// ile başlamalıdır.")
        }
        #expect(APIError.http(502).errorDescription == "Bitbucket returned HTTP 502.")
    }

    @Test func englishPlurals() {
        #expect(L10n.notifyComments(n: 1, names: "Ali") == "💬 1 new comment from Ali")
        #expect(L10n.notifyComments(n: 2, names: "Ali, Veli") == "💬 2 new comments from Ali, Veli")
    }

    @Test func relativeTimesFollowTheLanguage() {
        let localizer = Localizer()
        localizer.apply(.turkish)
        let text = Date.now.addingTimeInterval(-3 * 3600)
            .formatted(.relative(presentation: .named).locale(localizer.locale))
        #expect(text.contains("saat"))
    }
}

@MainActor
struct SupportTests {
    @Test func reportURLCarriesOnlyVersionSystemAndLanguage() throws {
        let url = Support.reportProblemURL(version: "0.2.8", system: "macOS 26.0", language: "Turkish (system)")
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(url.host() == "github.com")
        #expect(url.path() == "/itsberkelium/PR-Checker/issues/new")
        #expect(Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") }) == [
            "template": "bug_report.yml", "platform": "macOS", "version": "0.2.8",
            "os": "macOS 26.0", "language": "Turkish (system)",
        ])
    }

    @Test func languageIsDescribedInEnglish() {
        #expect(Support.languageDescription(language: .turkish, preference: .system) == "Turkish (system)")
        #expect(Support.languageDescription(language: .english, preference: .english) == "English")
    }
}
