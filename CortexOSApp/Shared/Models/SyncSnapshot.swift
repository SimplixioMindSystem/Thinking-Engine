//
//  SyncSnapshot.swift
//  CortexOS
//
//  Derived product snapshot. Apple apps build it on-device; optional developer
//  tooling can also encode and decode the same public model.
//

import Foundation

// MARK: - Snapshot

struct SyncSnapshot: Codable {
    let profile: SyncProfile
    let activeProject: ProjectContext?
    let priorities: PriorityBrief?
    let today: SyncTodayOutput?
    let weeklyReview: SyncWeeklyReview?
    let decisionReplay: SyncDecisionReplay?
    let newsletter: SyncNewsletter?
    let whatMattersNow: [SyncRankedSignal]?
    let signalTopPriorities: [SyncRankedPriority]?
    let decisionQueue: [SyncRankedSignal]?
    let actionReadyQueue: [SyncRankedSignal]?
    let recurringPatterns: [SyncRecurringPattern]?
    let unresolvedTensions: [SyncRankedSignal]?
    let contentCandidates: [SyncRankedSignal]?
    let resurfacedNow: [SyncRankedSignal]?
    let resurfacingRecurringTensions: [SyncRankedSignal]?
    let resurfacingWeeklyReviewCandidates: [SyncRankedSignal]?
    let resurfacingContentCandidates: [SyncRankedSignal]?
    let signalGraph: SyncSignalGraph?
    let signalMatchingCounts: SyncSignalMatchingCounts?
    let recentDecisions: [SyncDecision]
    let insights: [SyncInsight]
    let signals: [SyncSignal]
    let workingMemory: SyncWorkingMemory
    let syncedAt: String

    enum CodingKeys: String, CodingKey {
        case profile, priorities, today, insights, signals
        case weeklyReview = "weekly_review"
        case decisionReplay = "decision_replay"
        case newsletter
        case whatMattersNow = "what_matters_now"
        case signalTopPriorities = "signal_top_priorities"
        case decisionQueue = "decision_queue"
        case actionReadyQueue = "action_ready_queue"
        case recurringPatterns = "recurring_patterns"
        case unresolvedTensions = "unresolved_tensions"
        case contentCandidates = "content_candidates"
        case resurfacedNow = "resurfaced_now"
        case resurfacingRecurringTensions = "resurfacing_recurring_tensions"
        case resurfacingWeeklyReviewCandidates = "resurfacing_weekly_review_candidates"
        case resurfacingContentCandidates = "resurfacing_content_candidates"
        case signalGraph = "signal_graph"
        case signalMatchingCounts = "signal_matching_counts"
        case activeProject = "active_project"
        case recentDecisions = "recent_decisions"
        case workingMemory = "working_memory"
        case syncedAt = "synced_at"
    }
}

// MARK: - Signal Matching (deterministic ranked surfaces)

struct SyncSignalExplainability: Codable {
    let whyItSurfaced: String
    let topContributors: [String]
    let loweredConfidence: [String]
    let missingForReadiness: [String]
    let rankScore: Double

    enum CodingKeys: String, CodingKey {
        case whyItSurfaced = "why_it_surfaced"
        case topContributors = "top_contributors"
        case loweredConfidence = "lowered_confidence"
        case missingForReadiness = "missing_for_readiness"
        case rankScore = "rank_score"
    }
}

struct SyncSignalScoreBundle: Codable {
    let importance: Double
    let clarity: Double
    let decisionReadiness: Double
    let actionReadiness: Double
    let recurrence: Double
    let emotionalIntensity: Double
    let publishability: Double
    let staleness: Double

    enum CodingKeys: String, CodingKey {
        case importance, clarity, recurrence, staleness
        case decisionReadiness = "decision_readiness"
        case actionReadiness = "action_readiness"
        case emotionalIntensity = "emotional_intensity"
        case publishability
    }
}

struct SyncRankedSignal: Codable, Identifiable {
    let signalID: String
    let title: String
    let signalType: String
    let horizon: String
    let rankScore: Double
    let scores: SyncSignalScoreBundle
    let topics: [String]
    let sensitivity: String
    let explainability: SyncSignalExplainability
    let nextAction: String
    let capturedAt: String
    let resurfacingStatus: String?
    let resurfacingReason: String?
    let resurfacingTimeHorizon: String?
    let resurfacingAt: String?
    let resurfacingCount: Int?
    let resurfacingConfidence: Double?
    let resurfacingMode: String?
    let resurfacingExplanation: String?

    var id: String { signalID }

    enum CodingKeys: String, CodingKey {
        case title, horizon, scores, topics, sensitivity, explainability
        case signalID = "signal_id"
        case signalType = "signal_type"
        case rankScore = "rank_score"
        case nextAction = "next_action"
        case capturedAt = "captured_at"
        case resurfacingStatus = "resurfacing_status"
        case resurfacingReason = "resurfacing_reason"
        case resurfacingTimeHorizon = "resurfacing_time_horizon"
        case resurfacingAt = "resurfacing_at"
        case resurfacingCount = "resurfacing_count"
        case resurfacingConfidence = "resurfacing_confidence"
        case resurfacingMode = "resurfacing_mode"
        case resurfacingExplanation = "resurfacing_explanation"
    }
}

struct SyncRankedPriority: Codable, Identifiable {
    let title: String
    let why: String
    let action: String
    let signalID: String
    let rankScore: Double
    let horizon: String
    var id: String { signalID }

    enum CodingKeys: String, CodingKey {
        case title, why, action, horizon
        case signalID = "signal_id"
        case rankScore = "rank_score"
    }
}

struct SyncRecurringPattern: Codable, Identifiable {
    let topic: String
    let count: Int
    let unresolvedCount: Int
    let avgImportance: Double
    let sampleSignals: [String]
    var id: String { topic }

    enum CodingKeys: String, CodingKey {
        case topic, count
        case unresolvedCount = "unresolved_count"
        case avgImportance = "avg_importance"
        case sampleSignals = "sample_signals"
    }
}

struct SyncSignalGraphNode: Codable, Identifiable {
    let id: String
    let type: String
    let title: String
    let topics: [String]
    let sensitivity: String
}

struct SyncSignalGraphEdge: Codable, Identifiable {
    let from: String
    let to: String
    let relation: String
    let confidence: Double
    var id: String { "\(from)->\(to):\(relation)" }
}

struct SyncSignalGraph: Codable {
    let nodes: [SyncSignalGraphNode]
    let edges: [SyncSignalGraphEdge]
}

struct SyncSignalMatchingCounts: Codable {
    let signalsTotal: Int
    let signalsActive: Int
    let ignored: Int

    enum CodingKeys: String, CodingKey {
        case ignored
        case signalsTotal = "signals_total"
        case signalsActive = "signals_active"
    }
}

// MARK: - Newsletter

struct SyncNewsletterSafetyReport: Codable {
    let safeToPublish: Bool?
    let remainingConcerns: [String]?
    let recommendation: String?

    enum CodingKeys: String, CodingKey {
        case safeToPublish = "safe_to_publish"
        case remainingConcerns = "remaining_concerns"
        case recommendation
    }
}

struct SyncNewsletterTasteGate: Codable {
    let passed: Bool?
    let score: Int?
    let reasons: [String]?
}

struct SyncNewsletter: Codable {
    let status: String
    let mode: String
    let periodStart: String
    let periodEnd: String
    let safeToPublish: Bool
    let generatedAt: String
    let title: String
    let subtitle: String
    let preview: String
    let sourceCountTotal: Int
    let sourceCountUsable: Int
    let safetyReport: SyncNewsletterSafetyReport?
    let tasteGate: SyncNewsletterTasteGate?
    let markdownPath: String

    enum CodingKeys: String, CodingKey {
        case status, mode, title, subtitle, preview
        case periodStart = "period_start"
        case periodEnd = "period_end"
        case safeToPublish = "safe_to_publish"
        case generatedAt = "generated_at"
        case sourceCountTotal = "source_count_total"
        case sourceCountUsable = "source_count_usable"
        case safetyReport = "safety_report"
        case tasteGate = "taste_gate"
        case markdownPath = "markdown_path"
    }
}

extension SyncNewsletter {
    var passesAutomatedPublicationChecks: Bool {
        safetyReport?.safeToPublish == true &&
            tasteGate?.passed == true &&
            !markdownPath.isEmpty
    }

    var isEligibleForApproval: Bool {
        status == "needs_review" &&
            !safeToPublish &&
            passesAutomatedPublicationChecks
    }

    var isApprovedForSharing: Bool {
        status == "approved" &&
            safeToPublish &&
            passesAutomatedPublicationChecks
    }

    func withPublicationStatus(
        status: String,
        safeToPublish: Bool,
        recommendation: String
    ) -> SyncNewsletter {
        SyncNewsletter(
            status: status,
            mode: mode,
            periodStart: periodStart,
            periodEnd: periodEnd,
            safeToPublish: safeToPublish,
            generatedAt: generatedAt,
            title: title,
            subtitle: subtitle,
            preview: preview,
            sourceCountTotal: sourceCountTotal,
            sourceCountUsable: sourceCountUsable,
            safetyReport: SyncNewsletterSafetyReport(
                safeToPublish: safetyReport?.safeToPublish,
                remainingConcerns: safetyReport?.remainingConcerns,
                recommendation: recommendation
            ),
            tasteGate: tasteGate,
            markdownPath: markdownPath
        )
    }
}

struct NewsletterGenerateRequest: Codable {
    let period: String
    let mode: String
    let strictSafety: Bool
    let strictTaste: Bool

    enum CodingKeys: String, CodingKey {
        case period, mode
        case strictSafety = "strict_safety"
        case strictTaste = "strict_taste"
    }
}

struct NewsletterGenerationResult: Codable {
    let status: String
    let reason: String?
    let safeToPublish: Bool?
    let generatedAt: String?

    enum CodingKeys: String, CodingKey {
        case status, reason
        case safeToPublish = "safe_to_publish"
        case generatedAt = "generated_at"
    }
}

// MARK: - Decision Replay

struct SyncDecisionReplaySignal: Codable, Identifiable {
    var id: String { "\(title)-\(reason)" }
    let title: String
    let reason: String
}

struct SyncDecisionReplayPriority: Codable, Identifiable {
    var id: String { title }
    let title: String
    let why: String
    let action: String
}

struct SyncDecisionReplay: Codable {
    let date: String
    let signalsReviewed: Int
    let signalsKept: Int
    let signalsIgnored: Int
    let keptSignals: [SyncDecisionReplaySignal]
    let ignoredSignals: [SyncDecisionReplaySignal]
    let finalPriorities: [SyncDecisionReplayPriority]
    let summary: String
    let generatedAt: String

    enum CodingKeys: String, CodingKey {
        case date, summary
        case signalsReviewed = "signals_reviewed"
        case signalsKept = "signals_kept"
        case signalsIgnored = "signals_ignored"
        case keptSignals = "kept_signals"
        case ignoredSignals = "ignored_signals"
        case finalPriorities = "final_priorities"
        case generatedAt = "generated_at"
    }
}

// MARK: - Today Output

struct SyncTodayPriority: Codable, Identifiable {
    var id: String { "\(rank)-\(title)" }
    let rank: Int
    let title: String
    let why: String
    let action: String
}

struct SyncTodayOutput: Codable {
    let date: String
    let priorities: [SyncTodayPriority]
    let ignoredSignals: [String]
    let changesSinceYesterday: [String]
    let shareText: String
    let generatedAt: String

    enum CodingKeys: String, CodingKey {
        case date, priorities
        case ignoredSignals = "ignored_signals"
        case changesSinceYesterday = "changes_since_yesterday"
        case shareText = "share_text"
        case generatedAt = "generated_at"
    }
}

// MARK: - Weekly Review

struct SyncWeeklyReviewCountItem: Codable, Identifiable {
    var id: String { title }
    let title: String
    let count: Int
}

struct SyncWeeklyReview: Codable {
    let weekStart: String
    let weekEnd: String
    let periodLabel: String?
    let daysCovered: Int
    let quality: String?
    let confidence: Double?
    let topPriorities: [SyncWeeklyReviewCountItem]
    let topSignals: [SyncWeeklyReviewCountItem]
    let totalIgnoredSignals: Int
    let summary: String
    let recommendations: [String]
    let generatedAt: String

    enum CodingKeys: String, CodingKey {
        case summary, recommendations, quality, confidence
        case weekStart = "week_start"
        case weekEnd = "week_end"
        case periodLabel = "period_label"
        case daysCovered = "days_covered"
        case topPriorities = "top_priorities"
        case topSignals = "top_signals"
        case totalIgnoredSignals = "total_ignored_signals"
        case generatedAt = "generated_at"
    }
}

// MARK: - Profile (subset for sync)

struct SyncProfile: Codable {
    let name: String
    let role: String
    let goals: [String]
    let interests: [String]
    let currentProjects: [String]
    let ignoredTopics: [String]

    enum CodingKeys: String, CodingKey {
        case name, role, goals, interests
        case currentProjects = "current_projects"
        case ignoredTopics = "ignored_topics"
    }
}

// MARK: - Project

struct ProjectContext: Codable {
    let projectName: String
    let currentMilestone: String
    let activeBlockers: [String]
    let recentDecisions: [String]
    let architectureNotes: [String]
    let openQuestions: [String]

    enum CodingKeys: String, CodingKey {
        case projectName = "project_name"
        case currentMilestone = "current_milestone"
        case activeBlockers = "active_blockers"
        case recentDecisions = "recent_decisions"
        case architectureNotes = "architecture_notes"
        case openQuestions = "open_questions"
    }
}

// MARK: - Priority Brief

struct SyncPriority: Codable, Identifiable {
    var id: String { title }
    let rank: Int
    let title: String
    let whyItMatters: String
    let nextStep: String
    let source: String
    let relevanceScore: Double
    let tags: [String]

    enum CodingKeys: String, CodingKey {
        case rank, title, source, tags
        case whyItMatters = "why_it_matters"
        case nextStep = "next_step"
        case relevanceScore = "relevance_score"
    }
}

struct PriorityBrief: Codable {
    let date: String
    let priorities: [SyncPriority]
    let ignored: [String]
    let emergingSignals: [String]
    let changesSinceYesterday: [String]

    enum CodingKeys: String, CodingKey {
        case date, priorities, ignored
        case emergingSignals = "emerging_signals"
        case changesSinceYesterday = "changes_since_yesterday"
    }
}

// MARK: - Decision

struct SyncDecision: Codable, Identifiable {
    let id: String
    let decision: String
    let reason: String
    let project: String
    let assumptions: [String]
    let contextTags: [String]
    let createdAt: String
    let outcome: String
    let impactScore: Double

    enum CodingKeys: String, CodingKey {
        case id, decision, reason, project, assumptions, outcome
        case contextTags = "context_tags"
        case createdAt = "created_at"
        case impactScore = "impact_score"
    }
}

// MARK: - Insight

struct SyncInsight: Codable, Identifiable {
    let id: String
    let title: String
    let summary: String
    let whyItMatters: String
    let architecturalImplication: String
    let nextAction: String
    let confidence: Double
    let tags: [String]
    let relatedProject: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, title, summary, confidence, tags
        case whyItMatters = "why_it_matters"
        case architecturalImplication = "architectural_implication"
        case nextAction = "next_action"
        case relatedProject = "related_project"
        case createdAt = "created_at"
    }
}

// MARK: - Signal

struct SyncSignal: Codable, Identifiable {
    let id: String
    let topic: String
    let frequency: Int
    let strength: Double
    let status: String  // emerging, confirmed, fading, archived
    let firstSeen: String
    let lastSeen: String
    let sourceTitles: [String]

    enum CodingKeys: String, CodingKey {
        case id, topic, frequency, strength, status
        case firstSeen = "first_seen"
        case lastSeen = "last_seen"
        case sourceTitles = "source_titles"
    }
}

// MARK: - Working Memory

struct SyncWorkingMemory: Codable {
    let date: String
    let todaysPriorities: [String]
    let currentlyExploring: [String]
    let temporaryNotes: [String]

    enum CodingKeys: String, CodingKey {
        case date
        case todaysPriorities = "todays_priorities"
        case currentlyExploring = "currently_exploring"
        case temporaryNotes = "temporary_notes"
    }
}
