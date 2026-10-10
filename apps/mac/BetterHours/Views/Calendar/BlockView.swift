import BetterHoursCore
import SwiftUI

struct BlockView: View {
    let piece: DayPiece
    let palette: PaletteColor
    let format: TimeFormat

    private var shortBlock: Bool { piece.end.timeIntervalSince(piece.start) <= 30 * 60 }

    private var title: String {
        piece.block.title.isEmpty ? "Untitled" : piece.block.title
    }

    private var timeLabel: String {
        if piece.isRunningNow { return "\(format.clockTime(piece.start)) · running" }
        if piece.slot.count > 1 { return format.clockTime(piece.start) }
        return "\(format.clockTime(piece.start))–\(format.clockTime(piece.end))"
    }

    private var ink: Color { piece.isRunningNow ? Theme.accentText : palette.ink }
    private var fill: Color { piece.isRunningNow ? Theme.accentSoft : palette.fill }
    private var edge: Color { piece.isRunningNow ? Theme.accent : palette.ink }

    private var shape: UnevenRoundedRectangle {
        let bottom = piece.isRunningNow ? 0 : Radius.block
        return UnevenRoundedRectangle(
            topLeadingRadius: Radius.block, bottomLeadingRadius: bottom,
            bottomTrailingRadius: bottom, topTrailingRadius: Radius.block
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(Fonts.blockTitle).lineLimit(1)
            if !shortBlock {
                Text(timeLabel).font(Fonts.mono).lineLimit(1)
            }
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 6)
        .padding(.vertical, shortBlock ? 3 : 4)
        .padding(.leading, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(fill)
        .overlay(alignment: .leading) { edge.frame(width: 3) }
        .clipShape(shape)
    }
}
