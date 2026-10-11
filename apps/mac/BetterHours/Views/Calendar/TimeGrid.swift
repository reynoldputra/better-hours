import BetterHoursCore
import SwiftUI

struct TimeGrid: View {
    let model: CalendarModel
    let columns: [DayColumn]
    let library: LibraryModel
    let format: TimeFormat
    let now: Date
    let scrollHour: Int

    private static let hours = 24
    @State private var interactor = GridInteractor()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    gutter
                    ForEach(columns) { column in
                        DayColumnView(
                            column: column, model: model, library: library, format: format, now: now,
                            hoveredId: hoveredId
                        )
                        .zIndex(column.pieces.contains { $0.id == model.selectedBlockId } ? 1 : 0)
                    }
                }
                .frame(height: Metrics.hourHeight * CGFloat(Self.hours))
                .overlay {
                    PointerLayer(
                        onPointer: { interactor.handle($0, model: model, columns: columns) },
                        onKey: { interactor.handle($0, model: model) }
                    )
                }
            }
            .scrollIndicators(.hidden)
            .task {
                await Task.yield()
                proxy.scrollTo(scrollHour, anchor: .top)
            }
        }
    }

    private var hoveredId: UUID? {
        if case .block(let id, _) = interactor.hover { return id }
        return nil
    }

    private var gutter: some View {
        let day = columns.first?.start ?? now
        return VStack(spacing: 0) {
            ForEach(0..<Self.hours, id: \.self) { hour in
                Text(format.hourLabel(hour, on: day))
                    .font(Fonts.mono)
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .frame(width: Metrics.gutterWidth, height: Metrics.hourHeight, alignment: .topTrailing)
                    .id(hour)
            }
        }
    }
}

struct DayColumnView: View {
    let column: DayColumn
    let model: CalendarModel
    let library: LibraryModel
    let format: TimeFormat
    let now: Date
    let hoveredId: UUID?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                hourLines
                ForEach(column.pieces) { piece in
                    block(piece, width: geo.size.width)
                }
                if let drag = model.drag { preview(drag, width: geo.size.width) }
                if column.isToday { nowLine }
            }
        }
        .background(column.isToday ? Theme.accent.opacity(0.08) : column.isWeekend ? Theme.surface : Color.clear)
        .overlay(alignment: .leading) { Theme.line.frame(width: 1) }
    }

    private var hourLines: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { _ in
                Color.clear
                    .frame(height: Metrics.hourHeight)
                    .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
            }
        }
    }

    private func y(_ date: Date) -> CGFloat { GridGeometry.y(date, from: column.start) }

    private func block(_ piece: DayPiece, width: CGFloat) -> some View {
        let frame = GridGeometry.blockFrame(piece, columnStart: column.start, columnWidth: width)
        let palette = library.project(id: piece.block.projectId)?.color ?? .gray
        let dragged = model.drag?.kind.blockId == piece.id
        return BlockView(
            piece: piece, palette: palette, format: format,
            appearance: dragged ? .origin : .normal,
            isSelected: model.selectedBlockId == piece.id,
            isHovering: hoveredId == piece.id && model.drag == nil
        )
        .frame(width: frame.width, height: frame.height)
        .popover(isPresented: editorBinding(for: piece), arrowEdge: .trailing) {
            if let draft = model.editing, draft.id == piece.id {
                BlockEditorView(calendar: model, library: library, initial: draft)
            }
        }
        .padding(.leading, frame.minX)
        .padding(.top, frame.minY)
    }

    private func editorBinding(for piece: DayPiece) -> Binding<Bool> {
        Binding(
            get: { piece.isFirstPiece && model.editing?.id == piece.id },
            set: { if !$0, model.editing?.id == piece.id { model.cancelEditor() } }
        )
    }

    @ViewBuilder
    private func preview(_ drag: DragPreview, width: CGFloat) -> some View {
        let start = max(drag.start, column.start)
        let end = min(drag.end, column.end)
        if end > start, drag.kind != .create || end.timeIntervalSince(start) >= BlockRules.minimum {
            let top = y(start) + 1
            let height = max(y(end) - y(start) - 2, Metrics.minBlockHeight)
            let inset = GridGeometry.inset
            Group {
                if let id = drag.kind.blockId, let source = model.blocks.first(where: { $0.id == id }) {
                    BlockView(
                        piece: DayPiece(
                            block: source, start: start, end: end, slot: ColumnSlot(index: 0, count: 1),
                            isRunningNow: source.endAt == nil && column.isToday, isFirstPiece: false
                        ),
                        palette: library.project(id: source.projectId)?.color ?? .gray,
                        format: format, appearance: .dragging
                    )
                } else {
                    NewBlockGhost(start: drag.start, end: drag.end, format: format)
                }
            }
            .frame(width: width - 2 * inset, height: height)
            .padding(.leading, inset)
            .padding(.top, top)
            .allowsHitTesting(false)
        }
    }

    private var nowLine: some View {
        let top = y(now)
        return ZStack(alignment: .topLeading) {
            Theme.accent.frame(height: 2).padding(.leading, -4).offset(y: top - 1)
            Circle().fill(Theme.accent).frame(width: 10, height: 10).offset(x: -5, y: top - 5)
        }
    }
}
