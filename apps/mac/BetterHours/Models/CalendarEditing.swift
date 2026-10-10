import BetterHoursCore
import Foundation

enum BlockRules {
    static let snapMinutes = 5
    static let minimumMinutes = 5
    static var minimum: TimeInterval { TimeInterval(minimumMinutes * 60) }
}

enum ResizeEdge: Equatable, Sendable {
    case start, end
}

enum DragKind: Equatable {
    case create
    case move(id: UUID, grabOffset: TimeInterval)
    case resizeStart(id: UUID)
    case resizeEnd(id: UUID)

    var blockId: UUID? {
        switch self {
        case .create: nil
        case .move(let id, _), .resizeStart(let id), .resizeEnd(let id): id
        }
    }
}

struct DragPreview: Equatable {
    var kind: DragKind
    var start: Date
    var end: Date
}

struct EditorDraft: Equatable {
    let original: TimeBlock
    var title: String
    var notes: String
    var projectId: UUID?
    var tagIds: [UUID]
    var startAt: Date
    var endAt: Date?

    init(block: TimeBlock) {
        original = block
        title = block.title
        notes = block.notes
        projectId = block.projectId
        tagIds = block.tagIds
        startAt = block.startAt
        endAt = block.endAt
    }

    var id: UUID { original.id }
    var isRunning: Bool { original.endAt == nil }
    func duration(now: Date) -> TimeInterval { max(0, (endAt ?? now).timeIntervalSince(startAt)) }

    func validationError(now: Date) -> String? {
        if let endAt { return endAt <= startAt ? "End must be after start" : nil }
        return startAt >= now ? "Start must be before now" : nil
    }
}
