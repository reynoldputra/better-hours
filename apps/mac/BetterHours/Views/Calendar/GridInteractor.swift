import AppKit
import Observation

@Observable @MainActor
final class GridInteractor {
    private(set) var hover: GridGeometry.Hit = .empty

    private enum Press {
        case block(id: UUID, zone: GridGeometry.Zone, origin: CGPoint)
        case empty(origin: CGPoint)
    }

    private static let dragThreshold: CGFloat = 3
    private var press: Press?
    private var dragging = false

    func handle(_ event: PointerEvent, model: CalendarModel, columns: [DayColumn]) -> NSCursor? {
        let geometry = GridGeometry(columns: columns, width: event.width)
        let hit = geometry.hit(at: event.location)
        switch event.phase {
        case .down:
            dragging = false
            press = nil
            hover = hit
            switch hit {
            case .gutter:
                model.select(nil)
            case .block(let id, let zone):
                model.select(id)
                if event.clickCount >= 2 { model.openEditor(id: id) } else {
                    press = .block(id: id, zone: zone, origin: event.location)
                }
            case .empty:
                model.select(nil)
                press = .empty(origin: event.location)
            }
            return cursor(for: hit)
        case .dragged:
            drag(to: event.location, geometry: geometry, model: model)
            return dragCursor(model) ?? cursor(for: hit)
        case .up:
            let wasDragging = dragging
            press = nil
            dragging = false
            hover = hit
            if wasDragging { Task { await model.commitDrag() } }
            return cursor(for: hit)
        case .moved:
            hover = hit
            return cursor(for: hit)
        case .exited:
            hover = .empty
            return nil
        }
    }

    func handle(_ key: GridKey, model: CalendarModel) -> Bool {
        switch key {
        case .open:
            guard let id = model.selectedBlockId else { return false }
            model.openEditor(id: id)
        case .delete:
            guard let id = model.selectedBlockId else { return false }
            model.pendingDeleteId = id
        case .escape:
            guard model.drag != nil || model.selectedBlockId != nil else { return false }
            model.escape()
        }
        return true
    }

    private func drag(to point: CGPoint, geometry: GridGeometry, model: CalendarModel) {
        guard let press else { return }
        if !dragging {
            let origin = switch press {
            case .block(_, _, let origin), .empty(let origin): origin
            }
            guard hypot(point.x - origin.x, point.y - origin.y) >= Self.dragThreshold else { return }
            dragging = true
            switch press {
            case .block(let id, .body, let origin):
                model.beginMove(id: id, pointerTime: geometry.time(at: origin))
            case .block(let id, .topEdge, _):
                model.beginResize(id: id, edge: .start)
            case .block(let id, .bottomEdge, _):
                model.beginResize(id: id, edge: .end)
            case .empty(let origin):
                model.beginCreate(at: geometry.time(at: origin))
            }
        }
        if model.drag != nil { model.updateDrag(to: geometry.time(at: point)) }
    }

    private func cursor(for hit: GridGeometry.Hit) -> NSCursor {
        if case .block(_, let zone) = hit, zone != .body { return .resizeUpDown }
        return .arrow
    }

    private func dragCursor(_ model: CalendarModel) -> NSCursor? {
        guard dragging, let kind = model.drag?.kind else { return nil }
        switch kind {
        case .move: return .closedHand
        case .resizeStart, .resizeEnd: return .resizeUpDown
        case .create: return .crosshair
        }
    }
}
