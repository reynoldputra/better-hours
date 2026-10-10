import BetterHoursCore
import SwiftUI

struct BlockView: View {
    enum Appearance { case normal, origin, dragging }

    let piece: DayPiece
    let palette: PaletteColor
    let format: TimeFormat
    var appearance: Appearance = .normal
    var isSelected = false
    var isHovering = false

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
    private var bottomRadius: CGFloat { piece.isRunningNow ? 0 : Radius.block }

    private func shape(grow: CGFloat = 0) -> UnevenRoundedRectangle {
        let bottom = bottomRadius == 0 ? 0 : bottomRadius + grow
        return UnevenRoundedRectangle(
            topLeadingRadius: Radius.block + grow, bottomLeadingRadius: bottom,
            bottomTrailingRadius: bottom, topTrailingRadius: Radius.block + grow
        )
    }

    var body: some View {
        content
            .opacity(appearance == .dragging ? 0.75 : appearance == .origin ? 0.3 : 1)
            .shadow(color: shadowColor, radius: appearance == .dragging ? 12 : 6, y: appearance == .dragging ? 10 : 4)
            .background {
                if isSelected {
                    shape(grow: 4).fill(Theme.text).padding(-4)
                    shape(grow: 2).fill(Theme.background).padding(-2)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var shadowColor: Color {
        appearance == .dragging || (isHovering && appearance == .normal) ? Theme.shadow : .clear
    }

    private var accessibilityText: String {
        let end = piece.block.endAt == nil ? "running" : format.clockTime(piece.end)
        return "\(title), \(format.clockTime(piece.start)) to \(end)"
    }

    private var content: some View {
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
        .overlay(alignment: .bottom) {
            if piece.isRunningNow { Theme.accent.frame(height: 2) }
        }
        .overlay { grips }
        .clipShape(shape())
    }

    @ViewBuilder private var grips: some View {
        if isHovering && appearance == .normal && !shortBlock {
            VStack {
                if piece.start == piece.block.startAt { grip }
                Spacer(minLength: 0)
                if piece.block.endAt != nil, piece.end == piece.block.endAt { grip }
            }
            .padding(.vertical, 3)
        }
    }

    private var grip: some View {
        Capsule().fill(edge).frame(width: 20, height: 3)
    }
}

struct NewBlockGhost: View {
    let start: Date
    let end: Date
    let format: TimeFormat

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("New block").font(Fonts.blockTitle).lineLimit(1)
            Text("\(format.clockTime(start))–\(format.clockTime(end))").font(Fonts.mono).lineLimit(1)
        }
        .foregroundStyle(Theme.muted)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .padding(.leading, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: Radius.block))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.block)
                .strokeBorder(Theme.muted, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        }
        .accessibilityHidden(true)
    }
}
