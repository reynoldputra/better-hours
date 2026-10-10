import BetterHoursCore
import SwiftUI

struct TimeGrid: View {
    let columns: [DayColumn]
    let library: LibraryModel
    let format: TimeFormat
    let now: Date
    let scrollHour: Int

    private static let hours = 24

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    gutter
                    ForEach(columns) { column in
                        DayColumnView(column: column, library: library, format: format, now: now)
                    }
                }
                .frame(height: Metrics.hourHeight * CGFloat(Self.hours))
            }
            .scrollIndicators(.hidden)
            .onAppear { proxy.scrollTo(scrollHour, anchor: .top) }
        }
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
    let library: LibraryModel
    let format: TimeFormat
    let now: Date

    private let inset: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                hourLines
                ForEach(column.pieces) { piece in
                    block(piece, width: geo.size.width)
                }
                if column.isToday { nowLine }
            }
        }
        .background(column.isWeekend ? Theme.surface : Color.clear)
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

    private func y(_ date: Date) -> CGFloat {
        CGFloat(date.timeIntervalSince(column.start) / 3600) * Metrics.hourHeight
    }

    private func block(_ piece: DayPiece, width: CGFloat) -> some View {
        let count = CGFloat(piece.slot.count)
        let slotWidth = (width - 2 * inset) / count
        let top = y(piece.start) + 1
        let height = max(y(piece.end) - y(piece.start) - 2, Metrics.minBlockHeight)
        let palette = library.project(id: piece.block.projectId)?.color ?? .gray
        return BlockView(piece: piece, palette: palette, format: format)
            .frame(width: piece.slot.count > 1 ? slotWidth - 1 : slotWidth, height: height)
            .offset(x: inset + CGFloat(piece.slot.index) * slotWidth, y: top)
    }

    private var nowLine: some View {
        let top = y(now)
        return ZStack(alignment: .topLeading) {
            Theme.accent.frame(height: 2).padding(.leading, -4).offset(y: top - 1)
            Circle().fill(Theme.accent).frame(width: 10, height: 10).offset(x: -5, y: top - 5)
        }
    }
}
