import Foundation

struct LocalNewsletterDraft {
    let status: String
    let title: String
    let subtitle: String
    let preview: String
    let markdown: String
    let periodStart: String
    let periodEnd: String
    let sourceCountTotal: Int
    let sourceCountUsable: Int
    let safeToPublish: Bool
    let remainingConcerns: [String]
    let recommendation: String
    let tasteScore: Int
    let tasteReasons: [String]
}

enum LocalSynthesisEngine {
    static func weeklyReview(
        notes: [KnowledgeNote],
        priorities: LocalPriorityResult,
        now: Date = Date(),
        includeDemo: Bool = false
    ) -> SyncWeeklyReview? {
        let start = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: now)) ?? now
        let recent = notes.filter {
            !$0.archived &&
                (includeDemo || !$0.id.hasPrefix("demo-note-")) &&
                (date($0.updatedAt) ?? date($0.createdAt) ?? .distantPast) >= start
        }
        guard !recent.isEmpty else { return nil }

        let tags = recent.reduce(into: [String: Int]()) { counts, note in
            for tag in note.tags where !tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                counts[tag, default: 0] += 1
            }
        }
        let topSignals = tags
            .sorted { lhs, rhs in lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value }
            .prefix(5)
            .map { SyncWeeklyReviewCountItem(title: $0.key, count: $0.value) }
        let topPriorities = priorities.priorities.prefix(3).map {
            SyncWeeklyReviewCountItem(title: $0.title, count: 1)
        }
        let recommendations = priorities.priorities.prefix(3).map(\.nextStep)
        let repeated = topSignals.first.map { "\($0.title) appeared \($0.count) time\($0.count == 1 ? "" : "s")" }
            ?? "No theme repeated strongly yet"
        let quality = recent.count >= 5 ? "strong" : (recent.count >= 2 ? "useful" : "early")

        return SyncWeeklyReview(
            weekStart: dateOnly(start),
            weekEnd: dateOnly(now),
            periodLabel: "Last 7 days",
            daysCovered: 7,
            quality: quality,
            confidence: min(0.92, 0.45 + (Double(recent.count) * 0.07)),
            topPriorities: topPriorities,
            topSignals: topSignals,
            totalIgnoredSignals: priorities.ignoredTitles.count,
            summary: "Reviewed \(recent.count) captured signal\(recent.count == 1 ? "" : "s"). \(repeated). Your next focus stays limited to three priorities.",
            recommendations: recommendations,
            generatedAt: ISO8601DateFormatter().string(from: now)
        )
    }

    static func decisionReplay(
        notes: [KnowledgeNote],
        priorities: LocalPriorityResult,
        now: Date = Date(),
        includeDemo: Bool = false
    ) -> SyncDecisionReplay? {
        let active = notes.filter {
            !$0.archived && (includeDemo || !$0.id.hasPrefix("demo-note-"))
        }
        guard !active.isEmpty else { return nil }

        let selectedTitles = Set(priorities.priorities.map { normalized($0.title) })
        let kept = priorities.priorities.map {
            SyncDecisionReplaySignal(title: $0.title, reason: $0.whyItMatters)
        }
        let ignored = active
            .filter { !selectedTitles.contains(normalized($0.title)) }
            .prefix(5)
            .map {
                SyncDecisionReplaySignal(
                    title: $0.title,
                    reason: "Lower current readiness, relevance, or urgency than the selected three."
                )
            }
        let final = priorities.priorities.map {
            SyncDecisionReplayPriority(title: $0.title, why: $0.whyItMatters, action: $0.nextStep)
        }

        return SyncDecisionReplay(
            date: dateOnly(now),
            signalsReviewed: active.count,
            signalsKept: kept.count,
            signalsIgnored: max(0, active.count - kept.count),
            keptSignals: kept,
            ignoredSignals: ignored,
            finalPriorities: final,
            summary: "SimpliXio compared recency, readiness, repeated themes, profile context, and your feedback, then kept the three signals most likely to deserve action now.",
            generatedAt: ISO8601DateFormatter().string(from: now)
        )
    }

    static func newsletterDraft(
        notes: [KnowledgeNote],
        decisions: [SyncDecision],
        priorities: LocalPriorityResult,
        period: String,
        mode: String,
        now: Date = Date(),
        includeDemo: Bool = false
    ) -> LocalNewsletterDraft? {
        let days = period == "monthly" ? 30 : 7
        let start = Calendar.current.date(byAdding: .day, value: -(days - 1), to: Calendar.current.startOfDay(for: now)) ?? now
        let periodNotes = notes.filter {
            !$0.archived &&
                (includeDemo || !$0.id.hasPrefix("demo-note-")) &&
                (date($0.updatedAt) ?? date($0.createdAt) ?? .distantPast) >= start
        }
        let periodDecisions = decisions.filter {
            (includeDemo || !$0.id.hasPrefix("demo-decision-")) &&
                (date($0.createdAt) ?? .distantPast) >= start
        }
        let total = periodNotes.count + periodDecisions.count
        guard total > 0 else { return nil }

        var redactionReasons: Set<String> = []
        let usableNotes = periodNotes.compactMap { note -> KnowledgeNote? in
            guard !containsPrivateTag(note.tags) else {
                redactionReasons.insert("Private-tagged captures were excluded")
                return nil
            }
            var safe = note
            safe.title = redact(note.title, reasons: &redactionReasons)
            safe.insight = redact(note.insight, reasons: &redactionReasons)
            safe.implication = redact(note.implication, reasons: &redactionReasons)
            safe.action = redact(note.action, reasons: &redactionReasons)
            safe.sourceURL = ""
            return safe
        }
        let usableDecisions = periodDecisions.compactMap { decision -> SyncDecision? in
            guard !containsPrivateTag(decision.contextTags) else {
                redactionReasons.insert("Private-tagged decisions were excluded")
                return nil
            }
            return SyncDecision(
                id: decision.id,
                decision: redact(decision.decision, reasons: &redactionReasons),
                reason: redact(decision.reason, reasons: &redactionReasons),
                project: redact(decision.project, reasons: &redactionReasons),
                assumptions: decision.assumptions.map { redact($0, reasons: &redactionReasons) },
                contextTags: decision.contextTags,
                createdAt: decision.createdAt,
                outcome: redact(decision.outcome, reasons: &redactionReasons),
                impactScore: decision.impactScore
            )
        }
        let usableCount = usableNotes.count + usableDecisions.count
        guard usableCount > 0 else { return nil }

        let modeCopy = newsletterModeCopy(mode)
        let safePriorities = priorities.priorities.filter { priority in
            if containsPrivateTag(priority.tags) {
                redactionReasons.insert("Private-tagged priorities were excluded")
                return false
            }
            return true
        }.prefix(3).map { priority in
            (
                redact(priority.title, reasons: &redactionReasons),
                redact(priority.whyItMatters, reasons: &redactionReasons),
                redact(priority.nextStep, reasons: &redactionReasons)
            )
        }
        let repeatedTags = topTags(in: usableNotes)
        let lessons = Array(usableNotes.prefix(4))
        let title = modeCopy.title
        let subtitle = "A private review turned into a public-safe draft"

        var lines = ["# \(title)", "", subtitle, "", modeCopy.opening, ""]
        if !safePriorities.isEmpty {
            lines.append("## What mattered")
            lines.append("")
            for (index, priority) in safePriorities.enumerated() {
                lines.append("### \(index + 1). \(priority.0)")
                lines.append("")
                lines.append("**Why:** \(priority.1)")
                lines.append("")
                lines.append("**Next:** \(priority.2)")
                lines.append("")
            }
        }
        if !repeatedTags.isEmpty {
            lines.append("## What repeated")
            lines.append("")
            lines.append(repeatedTags.map { "`\($0)`" }.joined(separator: ", "))
            lines.append("")
        }
        if !lessons.isEmpty {
            lines.append("## Lessons worth keeping")
            lines.append("")
            for note in lessons {
                let lesson = note.insight.isEmpty ? note.title : note.insight
                lines.append("- \(lesson)")
            }
            lines.append("")
        }
        if let decision = usableDecisions.first {
            lines.append("## A decision to carry forward")
            lines.append("")
            lines.append("**\(decision.decision)**")
            if !decision.reason.isEmpty {
                lines.append("")
                lines.append(decision.reason)
            }
            lines.append("")
        }
        lines.append("## Takeaway")
        lines.append("")
        lines.append("Clarity did not come from tracking more. It came from choosing what mattered, understanding why, and taking one concrete action.")
        lines.append("")
        lines.append("---")
        lines.append("Drafted privately in SimpliXio. Reviewed by a human before publishing.")

        let markdown = lines.joined(separator: "\n")
        let publicationConcerns = publicationConcerns(in: markdown)
        let preview = markdown
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "*", with: "")
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
            .dropFirst(2)
            .prefix(4)
            .joined(separator: " ")
        let tasteReasons = usableCount < 2 ? ["Add another source for a stronger draft"] : []
        let tasteScore = min(100, 58 + (usableCount * 8) + (safePriorities.count * 4))
        let safetyNotes = Array(redactionReasons).sorted() + publicationConcerns

        return LocalNewsletterDraft(
            status: "needs_review",
            title: title,
            subtitle: subtitle,
            preview: String(preview.prefix(420)),
            markdown: markdown,
            periodStart: dateOnly(start),
            periodEnd: dateOnly(now),
            sourceCountTotal: total,
            sourceCountUsable: usableCount,
            safeToPublish: publicationConcerns.isEmpty,
            remainingConcerns: safetyNotes,
            recommendation: publicationConcerns.isEmpty
                ? "Automated checks passed. Review the full draft before approving it; SimpliXio never publishes automatically."
                : "Sensitive-looking text remains. Revise the source or draft before approval.",
            tasteScore: tasteScore,
            tasteReasons: tasteReasons
        )
    }

    private static func newsletterModeCopy(_ mode: String) -> (title: String, opening: String) {
        switch mode {
        case "personal-reflection":
            return ("What became clear this week", "A week of scattered thoughts became a smaller set of choices worth acting on.")
        case "product-builder-notes":
            return ("Builder notes: what mattered this week", "The useful work was not the loudest work. These were the signals that changed the next move.")
        case "technical-essay":
            return ("From project noise to one clear move", "Technical progress becomes easier to explain when decisions, constraints, and next actions stay connected.")
        default:
            return ("Three priorities from this week", "A short review of what mattered, what repeated, and what deserves action next.")
        }
    }

    private static func containsPrivateTag(_ tags: [String]) -> Bool {
        let privateTerms = ["private", "confidential", "client", "employer", "personal", "health", "legal", "financial", "secret", "internal"]
        return tags.contains { tag in
            let value = normalized(tag)
            return privateTerms.contains(where: value.contains)
        }
    }

    private static func redact(_ value: String, reasons: inout Set<String>) -> String {
        var result = value
        let patterns: [(String, String, String)] = [
            (#"[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, "[email removed]", "Email addresses were redacted"),
            (#"https?://[^\s)\]>]+"#, "[link removed]", "Links were redacted"),
            (#"(?i)\b(api[ _-]?key|access[ _-]?token|password|secret)\b\s*[:=]\s*[^\s,;]+"#, "[credential removed]", "Credential-like text was redacted"),
            (#"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----"#, "[private key removed]", "Private keys were redacted"),
            (#"/Users/[^\s]+"#, "[local path removed]", "Local file paths were redacted"),
            (#"\b[A-Za-z]:\\[^\s]+"#, "[local path removed]", "Local file paths were redacted"),
            (#"\b(?:\d{1,3}\.){3}\d{1,3}\b"#, "[network address removed]", "Network addresses were redacted"),
            (#"\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[1-5][0-9A-Fa-f]{3}-[89ABab][0-9A-Fa-f]{3}-[0-9A-Fa-f]{12}\b"#, "[identifier removed]", "Unique identifiers were redacted"),
            (#"(?<![\d-])\+?(?:\d[ .()]?){8,14}\d(?![\d-])"#, "[phone number removed]", "Phone numbers were redacted"),
            (#"\b(?:\d[ -]*?){13,19}\b"#, "[number removed]", "Long account-like numbers were redacted")
        ]
        for (pattern, replacement, reason) in patterns {
            let updated = result.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
            if updated != result { reasons.insert(reason) }
            result = updated
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func publicationConcerns(in markdown: String) -> [String] {
        let checks: [(String, String)] = [
            (#"[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, "An email address may remain"),
            (#"https?://[^\s)\]>]+"#, "A link may remain"),
            (#"(?i)\b(api[ _-]?key|access[ _-]?token|password|secret)\b\s*[:=]"#, "Credential-like text may remain"),
            (#"-----BEGIN [A-Z ]*PRIVATE KEY-----"#, "A private key may remain"),
            (#"/Users/[^\s]+|\b[A-Za-z]:\\[^\s]+"#, "A local file path may remain"),
            (#"\b(?:\d{1,3}\.){3}\d{1,3}\b"#, "A network address may remain"),
            (#"\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[1-5][0-9A-Fa-f]{3}-[89ABab][0-9A-Fa-f]{3}-[0-9A-Fa-f]{12}\b"#, "A unique identifier may remain"),
            (#"(?<![\d-])\+?(?:\d[ .()]?){8,14}\d(?![\d-])"#, "A phone number may remain"),
            (#"\b(?:\d[ -]*?){13,19}\b"#, "A long account-like number may remain"),
            (#"(?i)\b(confidential|under nda|do not publish|private client|internal project|passport|visa status|medical diagnosis|bank account|credit card number)\b"#, "Sensitive context may remain"),
        ]

        return checks.compactMap { pattern, concern in
            markdown.range(of: pattern, options: .regularExpression) == nil ? nil : concern
        }
    }

    private static func topTags(in notes: [KnowledgeNote]) -> [String] {
        let counts = notes.reduce(into: [String: Int]()) { result, note in
            for tag in note.tags where !containsPrivateTag([tag]) {
                result[tag, default: 0] += 1
            }
        }
        return counts.sorted { lhs, rhs in
            lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
        }.prefix(4).map(\.key)
    }

    private static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    private static func dateOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
    }
}
