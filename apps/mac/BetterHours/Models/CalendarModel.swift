import BetterHoursCore
import Foundation
import Observation

enum CalendarMode: Equatable, Sendable {
    case week, day
}

struct DayPiece: Identifiable, Equatable {
    var id: UUID { block.id }
    var block: TimeBlock
    var start: Date
    var end: Date
    var slot: ColumnSlot
    var isRunningNow: Bool
    var isFirstPiece: Bool
}

struct DayColumn: Identifiable, Equatable {
    var id: Date { start }
    var start: Date
    var end: Date
    var pieces: [DayPiece]
    var total: TimeInterval
    var isToday: Bool
    var isWeekend: Bool
}

@Observable @MainActor
final class CalendarModel {
    private(set) var mode: CalendarMode = .week
    private(set) var anchor: Date
    private(set) var blocks: [TimeBlock] = []
    private(set) var now: Date
    private(set) var loadError: String?
    private(set) var selectedBlockId: UUID?
    private(set) var drag: DragPreview?
    var editing: EditorDraft?
    var pendingDeleteId: UUID?
    var writeError: String?

    let calendar: Calendar
    private let store: LocalStore
    private let clock: @Sendable () -> Date
    private var pendingReload: Task<Void, Never>?
    private var reloadToken = 0
    private var dragSource: DragSource?
    private var isSaving = false

    private enum DragSource {
        case create(anchor: Date)
        case existing(TimeBlock)
    }

    init(store: LocalStore, clock: @escaping @Sendable () -> Date, calendar: Calendar) {
        self.store = store
        self.clock = clock
        self.calendar = calendar
        let current = clock()
        self.now = current
        self.anchor = calendar.startOfDay(for: current)
    }

    var range: DateInterval {
        switch mode {
        case .week:
            calendar.dateInterval(of: .weekOfYear, for: anchor) ?? dayInterval(anchor)
        case .day:
            dayInterval(anchor)
        }
    }

    var days: [Date] {
        let range = range
        var result: [Date] = []
        var day = range.start
        while day < range.end {
            result.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    var columns: [DayColumn] {
        days.map { column(for: $0) }
    }

    var containsToday: Bool { contains(range, now) }

    var initialScrollHour: Int {
        guard containsToday else { return 8 }
        return max(0, calendar.component(.hour, from: now) - 3)
    }

    var title: String {
        let range = range
        if mode == .day { return format("EEEEdMMMMyyyy", range.start) }
        let last = calendar.date(byAdding: .day, value: -1, to: range.end) ?? range.end
        let sameYear = calendar.component(.year, from: range.start) == calendar.component(.year, from: last)
        let sameMonth = sameYear && calendar.component(.month, from: range.start) == calendar.component(.month, from: last)
        if sameMonth { return "\(format("d", range.start)) – \(format("dMMMMyyyy", last))" }
        if sameYear { return "\(format("dMMM", range.start)) – \(format("dMMMyyyy", last))" }
        return "\(format("dMMMyyyy", range.start)) – \(format("dMMMyyyy", last))"
    }

    func setMode(_ newMode: CalendarMode) {
        guard newMode != mode else { return }
        mode = newMode
        scheduleReload()
    }

    func goToToday() {
        anchor = calendar.startOfDay(for: clock())
        now = clock()
        scheduleReload()
    }

    func goToNext() { shift(by: 1) }
    func goToPrevious() { shift(by: -1) }

    func refreshNow() { now = clock() }

    func reload() async {
        reloadToken += 1
        let token = reloadToken
        do {
            let loaded = try await store.blocks(in: range)
            guard token == reloadToken else { return }
            blocks = loaded
            loadError = nil
            reconcile()
        } catch {
            guard token == reloadToken else { return }
            loadError = "\(error)"
        }
    }

    private func reconcile() {
        let ids = Set(blocks.map(\.id))
        if let id = selectedBlockId, !ids.contains(id) { selectedBlockId = nil }
        if let id = editing?.id, !ids.contains(id) { editing = nil }
        if let id = pendingDeleteId, !ids.contains(id) { pendingDeleteId = nil }
        if case .existing(let block)? = dragSource, !ids.contains(block.id) { cancelDrag() }
    }

    func observeChanges() async {
        let changes = store.changes()
        await reload()
        for await _ in changes {
            refreshNow()
            await reload()
        }
    }

    func tickClock() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30))
            refreshNow()
        }
    }

    // MARK: Selection and drags

    func select(_ id: UUID?) { selectedBlockId = id }

    func escape() {
        if drag != nil { cancelDrag() } else { selectedBlockId = nil }
    }

    func beginCreate(at time: Date) {
        guard drag == nil else { return }
        selectedBlockId = nil
        let anchor = snapped(time)
        dragSource = .create(anchor: anchor)
        drag = DragPreview(kind: .create, start: anchor, end: anchor)
    }

    func beginMove(id: UUID, pointerTime: Date) {
        guard drag == nil, let block = block(id) else { return }
        selectedBlockId = id
        dragSource = .existing(block)
        drag = DragPreview(
            kind: .move(id: id, grabOffset: pointerTime.timeIntervalSince(block.startAt)),
            start: block.startAt, end: block.endAt ?? now
        )
    }

    func beginResize(id: UUID, edge: ResizeEdge) {
        guard drag == nil, let block = block(id), edge == .start || block.endAt != nil else { return }
        selectedBlockId = id
        dragSource = .existing(block)
        drag = DragPreview(
            kind: edge == .start ? .resizeStart(id: id) : .resizeEnd(id: id),
            start: block.startAt, end: block.endAt ?? now
        )
    }

    func updateDrag(to time: Date) {
        guard var preview = drag, let source = dragSource else { return }
        switch (preview.kind, source) {
        case (.create, .create(let anchor)):
            let day = dayInterval(anchor)
            let point = min(max(snapped(time), day.start), day.end)
            preview.start = min(anchor, point)
            preview.end = max(anchor, point)
        case (.move(_, let grab), .existing(let block)):
            var start = snapped(time.addingTimeInterval(-grab))
            if let end = block.endAt {
                if sameInstant(start, snapped(block.startAt)) { start = block.startAt }
                preview.start = start
                preview.end = start.addingTimeInterval(end.timeIntervalSince(block.startAt))
            } else {
                start = min(start, latestRunningStart)
                preview.start = sameInstant(start, snapped(block.startAt)) ? block.startAt : start
                preview.end = now
            }
        case (.resizeStart, .existing(let block)):
            let limit = block.endAt.map { $0.addingTimeInterval(-BlockRules.minimum) } ?? latestRunningStart
            let start = min(snapped(time), limit)
            preview.start = sameInstant(start, snapped(block.startAt)) ? block.startAt : start
        case (.resizeEnd, .existing(let block)):
            guard let original = block.endAt else { return }
            let end = max(snapped(time), block.startAt.addingTimeInterval(BlockRules.minimum))
            preview.end = sameInstant(end, snapped(original)) ? original : end
        default:
            return
        }
        drag = preview
    }

    func commitDrag() async {
        guard let preview = drag, let source = dragSource else { return }
        drag = nil
        dragSource = nil
        switch source {
        case .create:
            guard preview.end.timeIntervalSince(preview.start) >= BlockRules.minimum else { return }
            let created = TimeBlock(startAt: preview.start, endAt: preview.end)
            guard await perform({ try await store.save(created) }) else { return }
            await reload()
            selectedBlockId = created.id
            editing = EditorDraft(block: created)
        case .existing(let captured):
            guard let block = block(captured.id), block == captured else { return }
            var updated = block
            switch preview.kind {
            case .move:
                updated.startAt = preview.start
                if block.endAt != nil { updated.endAt = preview.end }
            case .resizeStart:
                updated.startAt = preview.start
            case .resizeEnd:
                updated.endAt = preview.end
            case .create:
                return
            }
            guard updated != block else { return }
            guard await perform({ try await store.save(updated) }) else { return }
            await reload()
        }
    }

    func cancelDrag() {
        drag = nil
        dragSource = nil
    }

    // MARK: Editor and delete

    func openEditor(id: UUID) {
        guard let block = block(id) else { return }
        selectedBlockId = id
        editing = EditorDraft(block: block)
    }

    func cancelEditor() { editing = nil }

    func saveEditor() async {
        guard let draft = editing, !isSaving, draft.validationError(now: now) == nil else { return }
        isSaving = true
        defer { isSaving = false }
        await reload()
        guard editing?.id == draft.id, var block = block(draft.id) else {
            editing = nil
            return
        }
        let original = draft.original
        if draft.title != original.title { block.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines) }
        if draft.notes != original.notes { block.notes = draft.notes }
        if draft.projectId != original.projectId { block.projectId = draft.projectId }
        if draft.tagIds != original.tagIds { block.tagIds = draft.tagIds }
        let start = edited(draft.startAt, from: original.startAt)
        if start != original.startAt { block.startAt = start }
        if let end = draft.endAt, let originalEnd = original.endAt {
            let newEnd = edited(end, from: originalEnd)
            if newEnd != originalEnd { block.endAt = newEnd }
        }
        let saved = block
        guard await perform({ try await store.save(saved) }) else { return }
        if editing?.id == draft.id { editing = nil }
        await reload()
    }

    func deleteBlock(id: UUID) async {
        pendingDeleteId = nil
        if editing?.id == id { editing = nil }
        if selectedBlockId == id { selectedBlockId = nil }
        guard await perform({ try await store.deleteBlock(id: id) }) else { return }
        await reload()
    }

    private func perform(_ work: () async throws -> Void) async -> Bool {
        do {
            try await work()
            return true
        } catch {
            writeError = "\(error)"
            return false
        }
    }

    private func block(_ id: UUID) -> TimeBlock? { blocks.first { $0.id == id } }

    private func snapped(_ date: Date) -> Date {
        let value = snap(date, toMinutes: BlockRules.snapMinutes, calendar: calendar)
        return Date(timeIntervalSinceReferenceDate: value.timeIntervalSinceReferenceDate.rounded())
    }

    private func sameInstant(_ a: Date, _ b: Date) -> Bool { abs(a.timeIntervalSince(b)) < 0.5 }

    private var latestRunningStart: Date {
        let limit = now.addingTimeInterval(-BlockRules.minimum)
        let value = snapped(limit)
        return value > limit ? value.addingTimeInterval(-TimeInterval(BlockRules.snapMinutes * 60)) : value
    }

    private func minuteFloor(_ date: Date) -> Date {
        calendar.dateInterval(of: .minute, for: date)?.start ?? date
    }

    private func edited(_ new: Date, from old: Date) -> Date {
        minuteFloor(new) == minuteFloor(old) ? old : minuteFloor(new)
    }

    private func shift(by steps: Int) {
        let days = mode == .week ? 7 * steps : steps
        anchor = calendar.date(byAdding: .day, value: days, to: anchor) ?? anchor
        scheduleReload()
    }

    private func scheduleReload() {
        pendingReload?.cancel()
        pendingReload = Task { await reload() }
    }

    private func contains(_ interval: DateInterval, _ date: Date) -> Bool {
        interval.start <= date && date < interval.end
    }

    private func dayInterval(_ day: Date) -> DateInterval {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return DateInterval(start: start, end: end)
    }

    private func column(for day: Date) -> DayColumn {
        let interval = dayInterval(day)
        let clipped: [TimeBlock] = blocks.compactMap { block in
            let start = max(block.startAt, interval.start)
            let end = min(block.endAt ?? now, interval.end)
            guard end > start else { return nil }
            var piece = block
            piece.startAt = start
            piece.endAt = end
            return piece
        }
        let visualMinimum = Metrics.minBlockHeight / Metrics.hourHeight * 3600
        let visual = clipped.map { piece in
            var extended = piece
            extended.endAt = max(piece.endAt ?? now, piece.startAt.addingTimeInterval(visualMinimum))
            return extended
        }
        let slots = layoutColumns(for: visual, now: now)
        let runningId = blocks.first { $0.endAt == nil }?.id
        let pieces = clipped.map { piece in
            let block = blocks.first { $0.id == piece.id } ?? piece
            return DayPiece(
                block: block,
                start: piece.startAt,
                end: piece.endAt ?? now,
                slot: slots[piece.id] ?? ColumnSlot(index: 0, count: 1),
                isRunningNow: piece.id == runningId && contains(interval, now),
                isFirstPiece: piece.startAt == block.startAt || interval.start == range.start
            )
        }
        return DayColumn(
            start: interval.start,
            end: interval.end,
            pieces: pieces.sorted { $0.start < $1.start },
            total: BetterHoursCore.total(of: blocks, in: interval, now: now),
            isToday: contains(interval, now),
            isWeekend: calendar.isDateInWeekend(interval.start)
        )
    }

    private func format(_ template: String, _ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = calendar.locale ?? .current
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}
