import Foundation

struct LocalSignalSurfaces {
    let whatMattersNow: [SyncRankedSignal]
    let topPriorities: [SyncRankedPriority]
    let decisionQueue: [SyncRankedSignal]
    let actionReadyQueue: [SyncRankedSignal]
    let recurringPatterns: [SyncRecurringPattern]
    let unresolvedTensions: [SyncRankedSignal]
    let contentCandidates: [SyncRankedSignal]
    let counts: SyncSignalMatchingCounts
}

enum LocalSignalEngine {
    private struct Candidate {
        let signal: SyncRankedSignal
        let explicitAction: Bool
        let explicitlyPublicSafe: Bool
    }

    static func build(
        notes: [KnowledgeNote],
        decisions: [SyncDecision],
        priorities: LocalPriorityResult,
        now: Date = Date(),
        includeDemo: Bool = false
    ) -> LocalSignalSurfaces {
        let visibleNotes = notes.filter {
            !$0.archived && (includeDemo || !$0.id.hasPrefix("demo-note-"))
        }
        let visibleDecisions = decisions.filter {
            $0.outcome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                (includeDemo || !$0.id.hasPrefix("demo-decision-"))
        }
        let tagFrequency = visibleNotes.reduce(into: [String: Int]()) { counts, note in
            for tag in note.tags.map(normalize).filter({ !$0.isEmpty }) {
                counts[tag, default: 0] += 1
            }
        }
        let priorityByTitle = Dictionary(
            uniqueKeysWithValues: priorities.priorities.map { (normalize($0.title), $0) }
        )

        var candidates = visibleNotes.map {
            noteCandidate(
                $0,
                priority: priorityByTitle[normalize($0.title)],
                tagFrequency: tagFrequency,
                now: now
            )
        }

        let noteTitles = Set(candidates.map { normalize($0.signal.title) })
        candidates.append(contentsOf: visibleDecisions.compactMap { decision in
            guard !noteTitles.contains(normalize(decision.decision)) else { return nil }
            return decisionCandidate(
                decision,
                priority: priorityByTitle[normalize(decision.decision)],
                now: now
            )
        })
        candidates.sort { lhs, rhs in
            if lhs.signal.rankScore == rhs.signal.rankScore {
                return lhs.signal.title.localizedCaseInsensitiveCompare(rhs.signal.title) == .orderedAscending
            }
            return lhs.signal.rankScore > rhs.signal.rankScore
        }

        let candidateByTitle = Dictionary(
            uniqueKeysWithValues: candidates.map { (normalize($0.signal.title), $0.signal) }
        )
        let whatMattersNow = priorities.priorities.compactMap {
            candidateByTitle[normalize($0.title)]
        }.prefix(3)
        let topPriorities = priorities.priorities.compactMap { priority -> SyncRankedPriority? in
            guard let signal = candidateByTitle[normalize(priority.title)] else { return nil }
            return SyncRankedPriority(
                title: priority.title,
                why: priority.whyItMatters,
                action: priority.nextStep,
                signalID: signal.signalID,
                rankScore: signal.rankScore,
                horizon: signal.horizon
            )
        }
        let rankedSignals = candidates.map(\.signal)
        let decisionQueue = rankedSignals.filter {
            ["decision", "question", "tension"].contains($0.signalType) &&
                $0.scores.decisionReadiness >= 55
        }.prefix(5)
        let actionReadyQueue = candidates.filter {
            $0.explicitAction && $0.signal.scores.actionReadiness >= 55
        }.map(\.signal).prefix(5)
        let unresolvedTensions = rankedSignals.filter {
            $0.signalType == "tension" && $0.scores.decisionReadiness >= 45
        }.prefix(5)
        let contentCandidates = candidates.filter {
            $0.explicitlyPublicSafe &&
                ["idea", "reflection", "content_seed", "thought"].contains($0.signal.signalType) &&
                $0.signal.scores.publishability >= 55
        }.map(\.signal).prefix(5)
        let recurringPatterns = buildRecurringPatterns(
            notes: visibleNotes,
            candidates: candidates,
            tagFrequency: tagFrequency
        )

        let nonDemoNotes = notes.filter { includeDemo || !$0.id.hasPrefix("demo-note-") }
        let nonDemoDecisions = decisions.filter { includeDemo || !$0.id.hasPrefix("demo-decision-") }
        return LocalSignalSurfaces(
            whatMattersNow: Array(whatMattersNow),
            topPriorities: topPriorities,
            decisionQueue: Array(decisionQueue),
            actionReadyQueue: Array(actionReadyQueue),
            recurringPatterns: recurringPatterns,
            unresolvedTensions: Array(unresolvedTensions),
            contentCandidates: Array(contentCandidates),
            counts: SyncSignalMatchingCounts(
                signalsTotal: nonDemoNotes.count + nonDemoDecisions.count,
                signalsActive: candidates.count,
                ignored: priorities.ignoredTitles.count + nonDemoNotes.filter(\.archived).count
            )
        )
    }

    private static func noteCandidate(
        _ note: KnowledgeNote,
        priority: SyncPriority?,
        tagFrequency: [String: Int],
        now: Date
    ) -> Candidate {
        let tags = note.tags.map(normalize).filter { !$0.isEmpty }
        let searchable = normalize(
            [note.title, note.insight, note.implication, note.action, tags.joined(separator: " ")]
                .joined(separator: " ")
        )
        let type = signalType(tags: tags, searchable: searchable)
        let privateTags = ["private", "confidential", "client", "personal", "health", "legal", "visa", "secret", "internal"]
        let publicTags = ["public", "public safe", "public ready", "newsletter", "content"]
        let isPrivate = privateTags.contains { tags.contains($0) }
        let explicitlyPublicSafe = !isPrivate && publicTags.contains { tags.contains($0) }
        let updatedAt = note.updatedAt.isEmpty ? note.createdAt : note.updatedAt
        let age = ageInDays(updatedAt, now: now)
        let recency = max(0, 100 - min(100, age * 4))
        let recurrence = min(100, Double(tags.map { tagFrequency[$0, default: 0] }.max() ?? 0) * 28)
        let clarity = min(100, 30 + fieldScore([note.insight, note.implication, note.action]))
        let actionReadiness = note.action.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 25.0 : 90.0
        let decisionReadiness: Double = ["decision", "question", "tension"].contains(type)
            ? min(95, 48 + (note.implication.isEmpty ? 0 : 22) + (note.action.isEmpty ? 0 : 20))
            : 35
        let urgency = containsAny(searchable, ["block", "deadline", "launch", "risk", "urgent", "today"])
        let emotionalIntensity = containsAny(searchable, ["tension", "worry", "stuck", "overwhelm", "frustrat"]) ? 72.0 : 30.0
        let importance = priority.map { min(100, max(55, $0.relevanceScore * 100)) }
            ?? min(92, 35 + (urgency ? 25 : 0) + (recurrence * 0.2) + (actionReadiness * 0.12))
        let publishability = explicitlyPublicSafe ? 78.0 : (isPrivate ? 0 : 20)
        let staleness = min(100, age * 4)
        let priorityBoost = priority == nil ? 0 : 18.0
        let rankScore = min(
            100,
            (importance * 0.32) +
                (recency * 0.18) +
                (actionReadiness * 0.18) +
                (decisionReadiness * 0.14) +
                (recurrence * 0.12) +
                priorityBoost
        )
        let horizon = priority != nil ? "now" : (rankScore >= 68 ? "today" : (rankScore >= 45 ? "this_week" : "later"))
        let contributors = contributors(
            isPriority: priority != nil,
            hasAction: !note.action.isEmpty,
            recurrence: recurrence,
            age: age,
            urgency: urgency
        )
        let missing = [
            note.implication.isEmpty ? "why it matters" : nil,
            note.action.isEmpty ? "a concrete next action" : nil,
        ].compactMap { $0 }
        let why: String
        if let priority, !priority.whyItMatters.isEmpty {
            why = priority.whyItMatters
        } else {
            why = contributors.prefix(2).joined(separator: "; ").capitalized + "."
        }

        return Candidate(
            signal: SyncRankedSignal(
                signalID: note.id,
                title: note.title,
                signalType: type,
                horizon: horizon,
                rankScore: rankScore,
                scores: SyncSignalScoreBundle(
                    importance: importance,
                    clarity: clarity,
                    decisionReadiness: decisionReadiness,
                    actionReadiness: actionReadiness,
                    recurrence: recurrence,
                    emotionalIntensity: emotionalIntensity,
                    publishability: publishability,
                    staleness: staleness
                ),
                topics: tags,
                sensitivity: explicitlyPublicSafe ? "public_safe" : "private",
                explainability: SyncSignalExplainability(
                    whyItSurfaced: why,
                    topContributors: contributors,
                    loweredConfidence: missing,
                    missingForReadiness: missing,
                    rankScore: rankScore
                ),
                nextAction: note.action.isEmpty
                    ? "Choose the smallest concrete step that moves this forward."
                    : note.action,
                capturedAt: updatedAt,
                resurfacingStatus: nil,
                resurfacingReason: nil,
                resurfacingTimeHorizon: nil,
                resurfacingAt: nil,
                resurfacingCount: nil,
                resurfacingConfidence: nil,
                resurfacingMode: nil,
                resurfacingExplanation: nil
            ),
            explicitAction: !note.action.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            explicitlyPublicSafe: explicitlyPublicSafe
        )
    }

    private static func decisionCandidate(
        _ decision: SyncDecision,
        priority: SyncPriority?,
        now: Date
    ) -> Candidate {
        let age = ageInDays(decision.createdAt, now: now)
        let recency = max(0, 100 - min(100, age * 4))
        let rawImpact = decision.impactScore <= 1 ? decision.impactScore * 100 : decision.impactScore
        let importance = min(100, max(55, rawImpact))
        let rankScore = min(100, (importance * 0.4) + (recency * 0.25) + 28 + (priority == nil ? 0 : 12))
        let reason = decision.reason.isEmpty
            ? "This open decision still needs a clear outcome."
            : decision.reason

        return Candidate(
            signal: SyncRankedSignal(
                signalID: decision.id,
                title: decision.decision,
                signalType: "decision",
                horizon: priority == nil ? (rankScore >= 68 ? "today" : "this_week") : "now",
                rankScore: rankScore,
                scores: SyncSignalScoreBundle(
                    importance: importance,
                    clarity: decision.reason.isEmpty ? 45 : 82,
                    decisionReadiness: 88,
                    actionReadiness: 65,
                    recurrence: 0,
                    emotionalIntensity: 30,
                    publishability: 0,
                    staleness: min(100, age * 4)
                ),
                topics: decision.contextTags,
                sensitivity: "private",
                explainability: SyncSignalExplainability(
                    whyItSurfaced: reason,
                    topContributors: ["open decision", "outcome not recorded"],
                    loweredConfidence: decision.reason.isEmpty ? ["decision rationale"] : [],
                    missingForReadiness: ["observable outcome"],
                    rankScore: rankScore
                ),
                nextAction: "Define the next observable outcome for this decision.",
                capturedAt: decision.createdAt,
                resurfacingStatus: nil,
                resurfacingReason: nil,
                resurfacingTimeHorizon: nil,
                resurfacingAt: nil,
                resurfacingCount: nil,
                resurfacingConfidence: nil,
                resurfacingMode: nil,
                resurfacingExplanation: nil
            ),
            explicitAction: true,
            explicitlyPublicSafe: false
        )
    }

    private static func buildRecurringPatterns(
        notes: [KnowledgeNote],
        candidates: [Candidate],
        tagFrequency: [String: Int]
    ) -> [SyncRecurringPattern] {
        tagFrequency.compactMap { tag, count -> SyncRecurringPattern? in
            guard count >= 2 else { return nil }
            let matching = candidates.filter { $0.signal.topics.map(normalize).contains(tag) }
            guard !matching.isEmpty else { return nil }
            let unresolved = matching.filter { !$0.explicitAction }.count
            let average = matching.map { $0.signal.scores.importance }.reduce(0, +) / Double(matching.count)
            let samples = notes.filter { $0.tags.map(normalize).contains(tag) }.prefix(3).map(\.title)
            return SyncRecurringPattern(
                topic: tag,
                count: count,
                unresolvedCount: unresolved,
                avgImportance: average,
                sampleSignals: samples
            )
        }
        .sorted {
            if $0.unresolvedCount != $1.unresolvedCount { return $0.unresolvedCount > $1.unresolvedCount }
            if $0.avgImportance != $1.avgImportance { return $0.avgImportance > $1.avgImportance }
            return $0.count > $1.count
        }
        .prefix(5)
        .map { $0 }
    }

    private static func signalType(tags: [String], searchable: String) -> String {
        if tags.contains("tension") || containsAny(searchable, ["tension", "conflict", "stuck", "blocker"]) { return "tension" }
        if tags.contains("decision") || containsAny(searchable, ["decide", "decision", "choose whether"]) { return "decision" }
        if tags.contains("question") || searchable.contains("?") { return "question" }
        if tags.contains("reflection") { return "reflection" }
        if tags.contains("idea") { return "idea" }
        if tags.contains("content") || tags.contains("newsletter") { return "content_seed" }
        return "thought"
    }

    private static func contributors(
        isPriority: Bool,
        hasAction: Bool,
        recurrence: Double,
        age: Double,
        urgency: Bool
    ) -> [String] {
        var values: [String] = []
        if isPriority { values.append("selected in today's top three") }
        if hasAction { values.append("has a concrete next action") }
        if recurrence >= 50 { values.append("repeats across recent captures") }
        if age <= 2 { values.append("recently updated") }
        if urgency { values.append("contains time-sensitive language") }
        return values.isEmpty ? ["recent captured context"] : values
    }

    private static func fieldScore(_ values: [String]) -> Double {
        Double(values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count) * 22
    }

    private static func ageInDays(_ value: String, now: Date) -> Double {
        guard let date = parseDate(value) else { return 14 }
        return max(0, now.timeIntervalSince(date) / 86_400)
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    private static func containsAny(_ value: String, _ terms: [String]) -> Bool {
        terms.contains(where: value.contains)
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .joined(separator: " ")
    }
}
