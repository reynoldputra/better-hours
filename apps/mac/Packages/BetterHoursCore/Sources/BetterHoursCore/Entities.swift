import Foundation

public enum PaletteColor: String, CaseIterable, Equatable, Sendable {
    case blue, orange, purple, pink, teal, yellow, red, gray
}

public struct TimeBlock: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var notes: String
    public var projectId: UUID?
    public var tagIds: [UUID]
    public var startAt: Date
    public var endAt: Date?

    public init(
        id: UUID = UUIDv7.generate(),
        title: String = "",
        notes: String = "",
        projectId: UUID? = nil,
        tagIds: [UUID] = [],
        startAt: Date,
        endAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.projectId = projectId
        self.tagIds = tagIds
        self.startAt = startAt
        self.endAt = endAt
    }
}

public struct Project: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var color: PaletteColor

    public init(id: UUID = UUIDv7.generate(), name: String, color: PaletteColor) {
        self.id = id
        self.name = name
        self.color = color
    }
}

public struct Tag: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String

    public init(id: UUID = UUIDv7.generate(), name: String) {
        self.id = id
        self.name = name
    }
}

public struct TimerSeed: Equatable, Sendable {
    public var title: String
    public var projectId: UUID?
    public var tagIds: [UUID]

    public init(title: String = "", projectId: UUID? = nil, tagIds: [UUID] = []) {
        self.title = title
        self.projectId = projectId
        self.tagIds = tagIds
    }
}
