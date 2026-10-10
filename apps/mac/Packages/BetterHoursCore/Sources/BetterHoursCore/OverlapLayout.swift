import Foundation

public struct ColumnSlot: Equatable, Sendable {
    public var index: Int
    public var count: Int

    public init(index: Int, count: Int) {
        self.index = index
        self.count = count
    }
}

public func layoutColumns(for blocks: [TimeBlock], now: Date) -> [UUID: ColumnSlot] {
    struct Item {
        var id: UUID
        var start: Date
        var end: Date
    }

    let items = blocks
        .map { Item(id: $0.id, start: $0.startAt, end: max($0.endAt ?? now, $0.startAt)) }
        .sorted { ($0.start, $0.end, $0.id.uuidString) < ($1.start, $1.end, $1.id.uuidString) }

    var result: [UUID: ColumnSlot] = [:]
    var cluster: [(id: UUID, index: Int)] = []
    var columnEnds: [Date] = []
    var clusterEnd = Date.distantPast

    func flush() {
        for member in cluster {
            result[member.id] = ColumnSlot(index: member.index, count: columnEnds.count)
        }
        cluster.removeAll()
        columnEnds.removeAll()
    }

    for item in items {
        if !cluster.isEmpty && item.start >= clusterEnd { flush() }
        let column = columnEnds.firstIndex { $0 <= item.start } ?? columnEnds.count
        if column == columnEnds.count {
            columnEnds.append(item.end)
        } else {
            columnEnds[column] = item.end
        }
        cluster.append((item.id, column))
        clusterEnd = cluster.count == 1 ? item.end : max(clusterEnd, item.end)
    }
    flush()
    return result
}
