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

    let calendar: Calendar
    private let store: LocalStore
    private let clock: @Sendable () -> Date
    private var pendingReload: Task<Void, Never>?
    private var reloadToken = 0

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
        } catch {
            guard token == reloadToken else { return }
            loadError = "\(error)"
        }
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
            DayPiece(
                block: blocks.first { $0.id == piece.id } ?? piece,
                start: piece.startAt,
                end: piece.endAt ?? now,
                slot: slots[piece.id] ?? ColumnSlot(index: 0, count: 1),
                isRunningNow: piece.id == runningId && contains(interval, now)
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
