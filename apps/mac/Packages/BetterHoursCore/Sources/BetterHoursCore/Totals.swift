import Foundation

public func total(of blocks: [TimeBlock], in interval: DateInterval, now: Date) -> TimeInterval {
    blocks.reduce(0) { sum, block in
        let start = max(block.startAt, interval.start)
        let end = min(block.endAt ?? now, interval.end)
        return end > start ? sum + end.timeIntervalSince(start) : sum
    }
}
