import BetterHoursCore
import SwiftUI

struct ColorSwatchPicker: View {
    let selected: PaletteColor
    let pick: (PaletteColor) -> Void

    var body: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(PaletteColor.allCases, id: \.self) { color in
                SwatchButton(color: color, isSelected: color == selected) { pick(color) }
            }
        }
        .padding(Spacing.md)
    }
}

private struct SwatchButton: View {
    let color: PaletteColor
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().strokeBorder(isSelected ? Theme.text : hovering ? Theme.muted : .clear, lineWidth: 2)
                Circle().fill(color.ink).frame(width: 20, height: 20)
            }
            .frame(width: 28, height: 28)
            .contentShape(Circle())
        }
        .buttonStyle(PressedOpacityStyle())
        .onHover { hovering = $0 }
        .help(color.displayName)
        .accessibilityLabel(color.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct PressedOpacityStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension PaletteColor {
    var displayName: String { rawValue.capitalized }
}
