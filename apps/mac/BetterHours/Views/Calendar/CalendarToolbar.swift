import SwiftUI

struct CalendarToolbar: View {
    let model: CalendarModel
    var leadingInset: CGFloat = 0

    var body: some View {
        HStack(spacing: Spacing.md) {
            iconButton("chevron.left", label: model.mode == .week ? "Previous week" : "Previous day") {
                model.goToPrevious()
            }
            iconButton("chevron.right", label: model.mode == .week ? "Next week" : "Next day") {
                model.goToNext()
            }
            Button("Today") { model.goToToday() }
                .buttonStyle(ToolbarButtonStyle(width: nil))
            Text(model.title)
                .font(Fonts.heading)
                .padding(.leading, Spacing.xs)
            Spacer(minLength: 0)
            modeSwitch
            iconButton("slider.horizontal.3", label: "Projects and tags") {}
        }
        .padding(.leading, Spacing.lg + leadingInset)
        .padding(.trailing, Spacing.lg)
        .frame(height: Metrics.toolbarHeight)
        .background(Theme.surface)
        .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
    }

    private var modeSwitch: some View {
        HStack(spacing: 0) {
            segment("Week", mode: .week)
            segment("Day", mode: .day)
        }
        .padding(2)
        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 8))
    }

    private func segment(_ title: String, mode: CalendarMode) -> some View {
        let selected = model.mode == mode
        return Button(title) { model.setMode(mode) }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: selected ? .semibold : .medium))
            .foregroundStyle(selected ? Theme.text : Theme.muted)
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: Radius.control)
                        .fill(Theme.background)
                        .shadow(color: Theme.shadow, radius: 1, y: 1)
                }
            }
            .contentShape(Rectangle())
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(ToolbarButtonStyle(width: Metrics.controlHeight))
        .accessibilityLabel(label)
    }
}

struct ToolbarButtonStyle: ButtonStyle {
    let width: CGFloat?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Fonts.bodyMedium)
            .foregroundStyle(Theme.text)
            .padding(.horizontal, width == nil ? Spacing.md : 0)
            .frame(width: width, height: Metrics.controlHeight)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: Radius.control))
            .overlay(RoundedRectangle(cornerRadius: Radius.control).stroke(Theme.line, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
