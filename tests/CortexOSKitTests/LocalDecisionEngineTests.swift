import XCTest
@testable import CortexOSKit

final class LocalDecisionEngineTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-08-08T12:00:00Z")!

    func testRankingFavorsActionableRepeatedProfileContext() {
        let notes = [
            note(
                id: "important",
                title: "Fix onboarding launch blocker",
                implication: "First-use clarity blocks the SimpliXio launch.",
                action: "Rewrite the opening screen today.",
                tags: ["launch", "onboarding"],
                updatedAt: "2026-08-07T12:00:00Z"
            ),
            note(
                id: "repeated",
                title: "Review onboarding evidence",
                implication: "The same onboarding issue repeated.",
                action: "Compare the latest first-run recording.",
                tags: ["onboarding"],
                updatedAt: "2026-08-07T11:00:00Z"
            ),
            note(
                id: "new-vague",
                title: "Maybe research another tool",
                implication: "",
                action: "",
                tags: ["research"],
                updatedAt: "2026-08-08T11:30:00Z"
            )
        ]
        let profile = UserProfile(goals: ["Ship SimpliXio launch"], currentProjects: ["SimpliXio"])

        let result = LocalPriorityEngine.rank(
            notes: notes,
            decisions: [],
            profile: profile,
            feedback: [],
            now: now
        )

        XCTAssertEqual(result.priorities.count, 3)
        XCTAssertEqual(result.priorities.first?.title, "Fix onboarding launch blocker")
        XCTAssertFalse(result.priorities.first?.whyItMatters.isEmpty ?? true)
        XCTAssertFalse(result.priorities.first?.nextStep.isEmpty ?? true)
    }

    func testNegativeFeedbackDemotesRepeatedlyUnhelpfulPriority() {
        let notes = [
            note(id: "a", title: "Polish secondary icon", action: "Polish it.", updatedAt: "2026-08-08T11:00:00Z"),
            note(id: "b", title: "Resolve launch crash", implication: "Users cannot finish onboarding.", action: "Fix the crash.", updatedAt: "2026-08-08T10:00:00Z")
        ]
        let feedback = (0..<5).map { index in
            LocalFeedbackEvent(
                id: "f\(index)",
                item: "Polish secondary icon",
                useful: false,
                createdAt: "2026-08-08T0\(index):00:00Z"
            )
        }

        let result = LocalPriorityEngine.rank(
            notes: notes,
            decisions: [],
            profile: .empty,
            feedback: feedback,
            now: now
        )

        XCTAssertEqual(result.priorities.first?.title, "Resolve launch crash")
    }

    func testActedPriorityLeavesTodaysFocus() {
        let completed = note(
            id: "done",
            title: "Finish the launch checklist",
            implication: "The release is blocked.",
            action: "Complete the last check.",
            updatedAt: "2026-08-08T10:00:00Z"
        )
        let remaining = note(
            id: "next",
            title: "Prepare the release note",
            implication: "Users need a clear summary.",
            action: "Draft three concise bullets.",
            updatedAt: "2026-08-08T09:00:00Z"
        )
        let feedback = LocalFeedbackEvent(
            item: completed.title,
            useful: true,
            acted: true,
            createdAt: "2026-08-08T11:30:00Z"
        )

        let result = LocalPriorityEngine.rank(
            notes: [completed, remaining],
            decisions: [],
            profile: .empty,
            feedback: [feedback],
            now: now
        )

        XCTAssertEqual(result.priorities.map(\.title), [remaining.title])
    }

    func testSynthesisBuildsReviewAndExplainableReplay() {
        let notes = [
            note(id: "a", title: "Clarify capture", implication: "Capture friction blocks value.", action: "Remove one field.", tags: ["capture"], updatedAt: "2026-08-08T10:00:00Z"),
            note(id: "b", title: "Test capture", implication: "The change needs proof.", action: "Run one UI test.", tags: ["capture"], updatedAt: "2026-08-07T10:00:00Z")
        ]
        let ranking = LocalPriorityEngine.rank(notes: notes, decisions: [], profile: .empty, feedback: [], now: now)

        let review = LocalSynthesisEngine.weeklyReview(notes: notes, priorities: ranking, now: now)
        let replay = LocalSynthesisEngine.decisionReplay(notes: notes, priorities: ranking, now: now)

        XCTAssertEqual(review?.topSignals.first?.title, "capture")
        XCTAssertEqual(review?.topSignals.first?.count, 2)
        XCTAssertEqual(replay?.signalsReviewed, 2)
        XCTAssertEqual(replay?.finalPriorities.count, 2)
        XCTAssertTrue(replay?.summary.contains("recency") == true)
    }

    func testNewsletterRedactsSensitivePatternsAndExcludesPrivateSources() {
        let notes = [
            note(
                id: "safe",
                title: "Contact founder@example.com about https://example.com",
                implication: "The API key: super-secret must not appear.",
                action: "Write a public-safe lesson.",
                tags: ["builder"],
                updatedAt: "2026-08-08T10:00:00Z"
            ),
            note(
                id: "private",
                title: "Confidential client roadmap",
                implication: "Never publish this.",
                action: "Keep private.",
                tags: ["client", "confidential"],
                updatedAt: "2026-08-08T09:00:00Z"
            )
        ]
        let ranking = LocalPriorityEngine.rank(notes: notes, decisions: [], profile: .empty, feedback: [], now: now)

        let draft = LocalSynthesisEngine.newsletterDraft(
            notes: notes,
            decisions: [],
            priorities: ranking,
            period: "weekly",
            mode: "weekly-lessons",
            now: now
        )

        XCTAssertNotNil(draft)
        XCTAssertFalse(draft?.markdown.contains("founder@example.com") ?? true)
        XCTAssertFalse(draft?.markdown.contains("https://example.com") ?? true)
        XCTAssertFalse(draft?.markdown.contains("super-secret") ?? true)
        XCTAssertFalse(draft?.markdown.contains("Confidential client roadmap") ?? true)
        XCTAssertEqual(draft?.sourceCountTotal, 2)
        XCTAssertEqual(draft?.sourceCountUsable, 1)
        XCTAssertTrue(draft?.remainingConcerns.isEmpty == false)
        XCTAssertTrue(draft?.safeToPublish == true)
    }

    func testNewsletterSafetyCheckBlocksSensitiveContextThatRemains() {
        let concerns = LocalSynthesisEngine.publicationConcerns(
            in: "A note about a confidential internal project."
        )

        XCTAssertEqual(concerns, ["Sensitive context may remain"])
    }

    func testNewsletterRequiresChecksAndApprovalBeforeSharing() {
        let draft = newsletter(status: "needs_review", safeToPublish: false)

        XCTAssertTrue(draft.isEligibleForApproval)
        XCTAssertFalse(draft.isApprovedForSharing)

        let approved = draft.withPublicationStatus(
            status: "approved",
            safeToPublish: true,
            recommendation: "Approved after review."
        )
        XCTAssertFalse(approved.isEligibleForApproval)
        XCTAssertTrue(approved.isApprovedForSharing)

        let rejected = draft.withPublicationStatus(
            status: "rejected",
            safeToPublish: false,
            recommendation: "Rejected."
        )
        XCTAssertFalse(rejected.isEligibleForApproval)
        XCTAssertFalse(rejected.isApprovedForSharing)
    }

    func testNewsletterPublicationGateFailsClosedWithoutTasteCheck() {
        let draft = newsletter(status: "needs_review", safeToPublish: false, tastePassed: nil)

        XCTAssertFalse(draft.isEligibleForApproval)
        XCTAssertFalse(draft.isApprovedForSharing)
    }

    func testLocalSignalSurfacesPopulateUsefulQueuesWithoutAService() {
        let notes = [
            note(
                id: "decision",
                title: "Decide the launch scope",
                implication: "The unresolved scope blocks launch.",
                action: "Remove one secondary feature.",
                tags: ["decision", "launch"],
                updatedAt: "2026-08-08T10:00:00Z"
            ),
            note(
                id: "repeat",
                title: "Review the launch promise",
                implication: "The promise must stay clear.",
                action: "Read the first screen aloud.",
                tags: ["launch"],
                updatedAt: "2026-08-07T10:00:00Z"
            ),
            note(
                id: "public",
                title: "Share one useful product lesson",
                implication: "Concrete proof builds trust.",
                action: "Draft the public-safe example.",
                tags: ["content", "public-safe"],
                updatedAt: "2026-08-08T09:00:00Z"
            ),
            note(
                id: "private",
                title: "Private client lesson",
                implication: "This must remain private.",
                action: "Keep it local.",
                tags: ["content", "private"],
                updatedAt: "2026-08-08T08:00:00Z"
            ),
        ]
        let priorities = LocalPriorityEngine.rank(
            notes: notes,
            decisions: [],
            profile: .empty,
            feedback: [],
            now: now
        )

        let surfaces = LocalSignalEngine.build(
            notes: notes,
            decisions: [],
            priorities: priorities,
            now: now
        )

        XCTAssertEqual(surfaces.whatMattersNow.count, 3)
        XCTAssertEqual(surfaces.decisionQueue.first?.title, "Decide the launch scope")
        XCTAssertFalse(surfaces.actionReadyQueue.isEmpty)
        XCTAssertEqual(surfaces.recurringPatterns.first?.topic, "launch")
        XCTAssertEqual(surfaces.contentCandidates.map(\.title), ["Share one useful product lesson"])
        XCTAssertEqual(surfaces.counts.signalsTotal, 4)
    }

    func testPreviewRankingRequiresExplicitDemoOptIn() {
        let demo = note(
            id: "demo-note-1",
            title: "Preview priority",
            implication: "Show the product clearly.",
            action: "Review the example.",
            updatedAt: "2026-08-08T10:00:00Z"
        )

        let normal = LocalPriorityEngine.rank(
            notes: [demo],
            decisions: [],
            profile: .empty,
            feedback: [],
            now: now
        )
        let preview = LocalPriorityEngine.rank(
            notes: [demo],
            decisions: [],
            profile: .empty,
            feedback: [],
            now: now,
            includeDemo: true
        )

        XCTAssertTrue(normal.priorities.isEmpty)
        XCTAssertEqual(preview.priorities.first?.title, "Preview priority")
        XCTAssertNotNil(
            LocalSynthesisEngine.weeklyReview(
                notes: [demo],
                priorities: preview,
                now: now,
                includeDemo: true
            )
        )
        XCTAssertNotNil(
            LocalSynthesisEngine.decisionReplay(
                notes: [demo],
                priorities: preview,
                now: now,
                includeDemo: true
            )
        )
    }

    private func newsletter(
        status: String,
        safeToPublish: Bool,
        tastePassed: Bool? = true
    ) -> SyncNewsletter {
        SyncNewsletter(
            status: status,
            mode: "weekly-lessons",
            periodStart: "2026-08-02",
            periodEnd: "2026-08-08",
            safeToPublish: safeToPublish,
            generatedAt: "2026-08-08T12:00:00Z",
            title: "Weekly lessons",
            subtitle: "A public-safe draft",
            preview: "A focused draft.",
            sourceCountTotal: 3,
            sourceCountUsable: 3,
            safetyReport: SyncNewsletterSafetyReport(
                safeToPublish: true,
                remainingConcerns: [],
                recommendation: "Review before sharing."
            ),
            tasteGate: SyncNewsletterTasteGate(
                passed: tastePassed,
                score: 90,
                reasons: []
            ),
            markdownPath: "/tmp/simplixio-newsletter.md"
        )
    }

    private func note(
        id: String,
        title: String,
        implication: String = "",
        action: String = "",
        tags: [String] = [],
        updatedAt: String
    ) -> KnowledgeNote {
        KnowledgeNote(
            id: id,
            title: title,
            insight: title,
            implication: implication,
            action: action,
            sourceURL: "",
            tags: tags,
            createdAt: updatedAt,
            updatedAt: updatedAt,
            archived: false
        )
    }
}
