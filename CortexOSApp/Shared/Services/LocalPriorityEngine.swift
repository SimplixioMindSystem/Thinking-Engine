import Foundation

struct LocalPriorityResult {
    let priorities: [SyncPriority]
    let ignoredTitles: [String]
}

enum LocalPriorityEngine {
    private struct Candidate {
        let title: String
        let why: String
        let action: String
        let source: String
        let score: Double
        let tags: [String]
    }

    static func rank(
        notes: [KnowledgeNote],
        decisions: [SyncDecision],
        profile: UserProfile,
        feedback: [LocalFeedbackEvent],
        now: Date = Date(),
        includeDemo: Bool = false
    ) -> LocalPriorityResult {
        let feedbackByItem = Dictionary(grouping: feedback, by: { normalize($0.item) })
        let activeNotes = notes.filter {
            !$0.archived &&
                (includeDemo || !$0.id.hasPrefix("demo-note-")) &&
                !wasActedOnToday(feedbackByItem[normalize($0.title)] ?? [], now: now)
        }
        let tagFrequency = activeNotes.reduce(into: [String: Int]()) { counts, note in
            for tag in note.tags.map(normalize).filter({ !$0.isEmpty }) {
                counts[tag, default: 0] += 1
            }
        }
        let profileTerms = meaningfulTerms(
            profile.goals + profile.currentProjects + profile.interests + profile.constraints
        )

        var candidates = activeNotes.map { note in
            Candidate(
                title: note.title,
                why: note.implication.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? fallbackWhy(for: note)
                    : note.implication,
                action: note.action.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Choose the smallest concrete step that moves this forward."
                    : note.action,
                source: note.sourceURL.isEmpty ? "on-device" : note.sourceURL,
                score: noteScore(
                    note,
                    now: now,
                    profileTerms: profileTerms,
                    tagFrequency: tagFrequency,
                    feedback: feedbackByItem[normalize(note.title)] ?? []
                ),
                tags: note.tags
            )
        }

        for decision in decisions where decision.outcome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard includeDemo || !decision.id.hasPrefix("demo-decision-") else { continue }
            let titleKey = normalize(decision.decision)
            guard !wasActedOnToday(feedbackByItem[titleKey] ?? [], now: now) else { continue }
            guard !candidates.contains(where: { normalize($0.title) == titleKey }) else { continue }
            let age = ageScore(from: decision.createdAt, now: now)
            let feedbackScore = scoreFeedback(feedbackByItem[titleKey] ?? [])
            candidates.append(
                Candidate(
                    title: decision.decision,
                    why: decision.reason.isEmpty ? "This open decision still needs a clear outcome." : decision.reason,
                    action: "Define the next observable outcome for this decision.",
                    source: "on-device decision",
                    score: min(1, 0.35 + (age * 0.35) + feedbackScore),
                    tags: decision.contextTags
                )
            )
        }

        candidates.sort {
            if $0.score == $1.score { return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            return $0.score > $1.score
        }

        let selected = selectDiverseCandidates(candidates, limit: 3)
        let selectedTitles = Set(selected.map { normalize($0.title) })
        let priorities = selected.enumerated().map { index, candidate in
            SyncPriority(
                rank: index + 1,
                title: candidate.title,
                whyItMatters: candidate.why,
                nextStep: candidate.action,
                source: candidate.source,
                relevanceScore: candidate.score,
                tags: candidate.tags
            )
        }
        let ignored = candidates
            .filter { !selectedTitles.contains(normalize($0.title)) }
            .prefix(5)
            .map(\.title)

        return LocalPriorityResult(priorities: priorities, ignoredTitles: ignored)
    }

    private static func noteScore(
        _ note: KnowledgeNote,
        now: Date,
        profileTerms: Set<String>,
        tagFrequency: [String: Int],
        feedback: [LocalFeedbackEvent]
    ) -> Double {
        let searchable = normalize(
            [note.title, note.insight, note.implication, note.action, note.tags.joined(separator: " ")]
                .joined(separator: " ")
        )
        let profileMatches = profileTerms.filter { searchable.contains($0) }.count
        let profileScore = min(0.2, Double(profileMatches) * 0.05)
        let recurrence = note.tags
            .map(normalize)
            .map { tagFrequency[$0, default: 0] }
            .max() ?? 0
        let recurrenceScore = min(0.16, Double(max(0, recurrence - 1)) * 0.05)
        let readiness = note.action.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 0.14
        let consequence = note.implication.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 0.1
        let urgencyWords = ["block", "deadline", "launch", "risk", "urgent", "today", "decision"]
        let urgency = urgencyWords.contains(where: searchable.contains) ? 0.1 : 0
        let recency = ageScore(from: note.updatedAt.isEmpty ? note.createdAt : note.updatedAt, now: now) * 0.35

        return min(1, max(0.05, 0.15 + recency + readiness + consequence + urgency + profileScore + recurrenceScore + scoreFeedback(feedback)))
    }

    private static func scoreFeedback(_ events: [LocalFeedbackEvent]) -> Double {
        events.sorted {
            (parseDate($0.createdAt) ?? .distantPast) > (parseDate($1.createdAt) ?? .distantPast)
        }.prefix(8).enumerated().reduce(0) { score, entry in
            let (offset, event) = entry
            let weight = 1 / Double(offset + 1)
            var delta = event.useful ? 0.08 : -0.2
            // Completing today's action must not make that exact item rank higher.
            if event.acted == true { delta = -0.05 }
            if event.acted == false { delta -= 0.04 }
            return score + (delta * weight)
        }
    }

    private static func wasActedOnToday(_ events: [LocalFeedbackEvent], now: Date) -> Bool {
        guard let latest = events.max(by: {
            (parseDate($0.createdAt) ?? .distantPast) < (parseDate($1.createdAt) ?? .distantPast)
        }),
              latest.acted == true,
              let actedAt = parseDate(latest.createdAt) else {
            return false
        }
        return Calendar.current.isDate(actedAt, inSameDayAs: now)
    }

    private static func selectDiverseCandidates(_ candidates: [Candidate], limit: Int) -> [Candidate] {
        var selected: [Candidate] = []
        var remaining = candidates

        while selected.count < limit, !remaining.isEmpty {
            let selectedTags = Set(selected.flatMap(\.tags).map(normalize))
            let ranked = remaining.enumerated().map { index, candidate -> (Int, Double) in
                let overlap = Set(candidate.tags.map(normalize)).intersection(selectedTags).count
                return (index, candidate.score - min(0.12, Double(overlap) * 0.04))
            }
            guard let winner = ranked.max(by: { $0.1 < $1.1 }) else { break }
            selected.append(remaining.remove(at: winner.0))
        }
        return selected
    }

    private static func ageScore(from rawDate: String, now: Date) -> Double {
        guard let date = parseDate(rawDate) else { return 0.2 }
        let days = max(0, now.timeIntervalSince(date) / 86_400)
        return max(0, 1 - (days / 30))
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    private static func fallbackWhy(for note: KnowledgeNote) -> String {
        if !note.insight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return String(note.insight.prefix(180))
        }
        return "This recent signal may change what deserves attention now."
    }

    private static func meaningfulTerms(_ values: [String]) -> Set<String> {
        let stopWords: Set<String> = ["and", "for", "from", "into", "the", "this", "that", "with", "your"]
        return Set(values.flatMap {
            normalize($0).split(separator: " ").map(String.init)
        }.filter { $0.count > 2 && !stopWords.contains($0) })
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .joined(separator: " ")
    }
}
