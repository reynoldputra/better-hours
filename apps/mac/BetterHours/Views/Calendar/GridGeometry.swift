import BetterHoursCore
import CoreGraphics
import Foundation

struct GridGeometry {
    static let inset: CGFloat = 3
    static let edgeZone: CGFloat = 5

    enum Zone: Equatable { case body, topEdge, bottomEdge }
    enum Hit: Equatable {
        case gutter
        case empty
        case block(id: UUID, zone: Zone)
    }

    let columns: [DayColumn]
    let width: CGFloat

    var columnWidth: CGFloat {
        columns.isEmpty ? 0 : max(0, (width - Metrics.gutterWidth) / CGFloat(columns.count))
    }

    static func y(_ date: Date, from start: Date) -> CGFloat {
        CGFloat(date.timeIntervalSince(start) / 3600) * Metrics.hourHeight
    }

    static func blockFrame(_ piece: DayPiece, columnStart: Date, columnWidth: CGFloat) -> CGRect {
        let count = CGFloat(piece.slot.count)
        let slotWidth = (columnWidth - 2 * inset) / count
        let top = y(piece.start, from: columnStart) + 1
        let height = max(y(piece.end, from: columnStart) - y(piece.start, from: columnStart) - 2, Metrics.minBlockHeight)
        return CGRect(
            x: inset + CGFloat(piece.slot.index) * slotWidth,
            y: top,
            width: piece.slot.count > 1 ? slotWidth - 1 : slotWidth,
            height: height
        )
    }

    func columnIndex(atX x: CGFloat) -> Int? {
        guard x >= Metrics.gutterWidth, !columns.isEmpty, columnWidth > 0 else { return nil }
        return min(columns.count - 1, Int((x - Metrics.gutterWidth) / columnWidth))
    }

    func time(at point: CGPoint) -> Date {
        guard !columns.isEmpty else { return Date() }
        let index = columnIndex(atX: point.x) ?? (point.x < Metrics.gutterWidth ? 0 : columns.count - 1)
        let y = min(max(point.y, 0), Metrics.hourHeight * 24)
        return columns[index].start.addingTimeInterval(Double(y / Metrics.hourHeight) * 3600)
    }

    func hit(at point: CGPoint) -> Hit {
        guard let index = columnIndex(atX: point.x) else { return .gutter }
        let column = columns[index]
        let local = CGPoint(x: point.x - Metrics.gutterWidth - CGFloat(index) * columnWidth, y: point.y)
        for piece in column.pieces.reversed() {
            let frame = Self.blockFrame(piece, columnStart: column.start, columnWidth: columnWidth)
            guard frame.contains(local) else { continue }
            let edge = min(Self.edgeZone, frame.height / 3)
            let block = piece.block
            if piece.start == block.startAt, local.y - frame.minY < edge {
                return .block(id: block.id, zone: .topEdge)
            }
            if let end = block.endAt, piece.end == end, frame.maxY - local.y < edge {
                return .block(id: block.id, zone: .bottomEdge)
            }
            return .block(id: block.id, zone: .body)
        }
        return .empty
    }
}
