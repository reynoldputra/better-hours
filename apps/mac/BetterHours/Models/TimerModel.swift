import BetterHoursCore
import Foundation
import Observation

@Observable @MainActor
final class TimerModel {
    private(set) var running: TimeBlock?
    private(set) var lastEnded: TimeBlock?
    private(set) var todayTotal: TimeInterval = 0
    private(set) var weekTotal: TimeInterval = 0
    private(set) var now: Date
    private(set) var writeError: String?

    private let store: LocalStore
    private let clock: @Sendable () -> Date
    private let calendar: Calendar
    private var weekBlocks: [TimeBlock] = []
    private var loadedWeek: DateInterval?
    private var reloadToken = 0
    private var startPending = false
    private var writeTail: Task<Void, Never> = Task {}
    private let tickInterval: Duration
    private var ticker: Task<Void, Never>?

    init(store: LocalStore, clock: @escaping @Sendable () -> Date, calendar: Calendar, tickInterval: Duration = .seconds(1)) {
        self.store = store
        self.tickInterval = tickInterval
        self.clock = clock
        self.calendar = calendar
        self.now = clock()
    }

    var isRunning: Bool { running != nil }

    var elapsed: TimeInterval {
        guard let running else { return 0 }
        return max(0, now.timeIntervalSince(running.startAt))
    }

    func dismissError() { writeError = nil }

    // MARK: Actions

    func start(title: String) async {
        await begin(TimerSeed(title: title.trimmingCharacters(in: .whitespacesAndNewlines), projectId: nil, tagIds: []))
    }

    func stop() async {
        await serialized { [self] in
            await perform { _ = try await store.stopTimer(now: clock()) }
        }
    }

    func continueLast() async {
        guard let last = lastEnded else { return }
        await begin(TimerSeed(title: last.title, projectId: last.projectId, tagIds: last.tagIds))
    }

    func renameRunning(_ title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        await updateRunning { block in
            guard block.title != trimmed else { return false }
            block.title = trimmed
            return true
        }
    }

    func setRunningProject(_ id: UUID?) async {
        await updateRunning { block in
            guard block.projectId != id else { return false }
            block.projectId = id
            return true
        }
    }

    // MARK: Clock and loading

    func tick() {
        now = clock()
        if let week = loadedWeek, !(week.start <= now && now < week.end) {
            Task { await refresh() }
        } else {
            recomputeTotals()
        }
    }

    func observeChanges() async {
        let changes = store.changes()
        await refresh()
        for await _ in changes { await refresh() }
    }

    func refresh() async {
        reloadToken += 1
        let token = reloadToken
        let current = clock()
        let week = calendar.dateInterval(of: .weekOfYear, for: current)
            ?? DateInterval(start: calendar.startOfDay(for: current), duration: 7 * 86_400)
        do {
            let runningBlock = try await store.runningBlock()
            let last = try await store.lastEndedBlock()
            let blocks = try await store.blocks(in: week)
            guard token == reloadToken else { return }
            running = runningBlock
            lastEnded = last
            weekBlocks = blocks
            loadedWeek = week
            now = current
            recomputeTotals()
            updateTicker()
        } catch {
            guard token == reloadToken else { return }
            writeError = "\(error)"
        }
    }

    // MARK: Private

    private func begin(_ seed: TimerSeed) async {
        guard !startPending else { return }
        startPending = true
        await serialized { [self] in
            await perform { _ = try await store.startTimer(seed: seed, now: clock()) }
        }
        startPending = false
    }

    // Re-reads the running block inside the write queue so a stale copy never reopens a stopped block.
    private func updateRunning(_ mutate: @escaping @MainActor (inout TimeBlock) -> Bool) async {
        guard running != nil else { return }
        await serialized { [self] in
            await perform {
                guard var block = try await store.runningBlock(), mutate(&block) else { return }
                try await store.save(block)
            }
        }
    }

    private func serialized(_ work: @escaping @MainActor () async -> Void) async {
        let previous = writeTail
        let task = Task { @MainActor in
            await previous.value
            await work()
        }
        writeTail = task
        await task.value
    }

    private func perform(_ work: () async throws -> Void) async {
        do {
            try await work()
        } catch {
            writeError = "\(error)"
        }
        await refresh()
    }

    private func recomputeTotals() {
        let day = calendar.dateInterval(of: .day, for: now)
            ?? DateInterval(start: calendar.startOfDay(for: now), duration: 86_400)
        todayTotal = total(of: weekBlocks, in: day, now: now)
        weekTotal = loadedWeek.map { total(of: weekBlocks, in: $0, now: now) } ?? 0
    }

    private func updateTicker() {
        if running == nil {
            ticker?.cancel()
            ticker = nil
        } else if ticker == nil {
            let interval = tickInterval
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: interval)
                    guard let self, !Task.isCancelled else { return }
                    self.tick()
                }
            }
        }
    }
}
