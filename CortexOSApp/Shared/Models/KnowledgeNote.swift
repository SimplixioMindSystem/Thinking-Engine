//
//  KnowledgeNote.swift
//  CortexOS
//
//  The core knowledge note model — mirrors the Python KnowledgeNote dataclass.
//

import Foundation

struct KnowledgeNote: Codable, Identifiable, Hashable {
    let id: String
    var title: String
    var insight: String
    var implication: String
    var action: String
    var sourceURL: String
    var tags: [String]
    var createdAt: String
    var updatedAt: String
    var archived: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, insight, implication, action, tags, archived
        case sourceURL   = "source_url"
        case createdAt   = "created_at"
        case updatedAt   = "updated_at"
    }

    // MARK: - Convenience

    var createdDate: Date? {
        ISO8601DateFormatter().date(from: createdAt)
    }

    var displayTags: String {
        tags.map { "#\($0)" }.joined(separator: " ")
    }

    static let example = KnowledgeNote(
        id: "abc123",
        title: "Onboarding clarity is blocking first-use value",
        insight: "The first screen should make 3 priorities, why, and action obvious immediately.",
        implication: "Users cannot want SimpliXio if the value takes too long to understand.",
        action: "Reduce the first screen to capture, 3 priorities, and one next action.",
        sourceURL: "",
        tags: ["onboarding", "focus"],
        createdAt: ISO8601DateFormatter().string(from: .now),
        updatedAt: "",
        archived: false
    )
}

// MARK: - Create / Update DTOs

struct NoteCreateRequest: Codable {
    var title: String = ""
    var insight: String = ""
    var implication: String = ""
    var action: String = ""
    var sourceURL: String = ""
    var tags: [String] = []

    enum CodingKeys: String, CodingKey {
        case title, insight, implication, action, tags
        case sourceURL = "source_url"
    }
}

struct NoteUpdateRequest: Codable {
    var title: String?
    var insight: String?
    var implication: String?
    var action: String?
    var sourceURL: String?
    var tags: [String]?
    var archived: Bool?

    enum CodingKeys: String, CodingKey {
        case title, insight, implication, action, tags, archived
        case sourceURL = "source_url"
    }
}
