//
//  PrivateSyncPayload.swift
//  CortexOS
//
//  Private, Apple-account-backed state shared by iPhone, Mac, and Apple Watch.
//  Derived views such as Today and Weekly Review are rebuilt on each device.
//

import Foundation

struct LocalFeedbackEvent: Codable, Identifiable, Hashable {
    let id: String
    let item: String
    let useful: Bool
    let acted: Bool?
    let createdAt: String

    init(
        id: String = UUID().uuidString,
        item: String,
        useful: Bool,
        acted: Bool? = nil,
        createdAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.item = item
        self.useful = useful
        self.acted = acted
        self.createdAt = createdAt
    }
}

struct PrivateSyncPayload: Codable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    var notes: [KnowledgeNote]
    var deletedNoteIDs: [String: String]
    var profile: UserProfile
    var profileUpdatedAt: String
    var decisions: [SyncDecision]
    var decisionUpdatedAt: [String: String]
    var insights: [SyncInsight]
    var feedback: [LocalFeedbackEvent]
    var modifiedAt: String
    var deviceID: String

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        notes: [KnowledgeNote],
        deletedNoteIDs: [String: String],
        profile: UserProfile,
        profileUpdatedAt: String,
        decisions: [SyncDecision],
        decisionUpdatedAt: [String: String],
        insights: [SyncInsight],
        feedback: [LocalFeedbackEvent],
        modifiedAt: String,
        deviceID: String
    ) {
        self.schemaVersion = schemaVersion
        self.notes = notes
        self.deletedNoteIDs = deletedNoteIDs
        self.profile = profile
        self.profileUpdatedAt = profileUpdatedAt
        self.decisions = decisions
        self.decisionUpdatedAt = decisionUpdatedAt
        self.insights = insights
        self.feedback = feedback
        self.modifiedAt = modifiedAt
        self.deviceID = deviceID
    }
}
