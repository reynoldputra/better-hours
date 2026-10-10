import SwiftUI

extension View {
    func calendarToolbar(_ model: CalendarModel) -> some View {
        modifier(CalendarToolbarModifier(model: model))
    }
}

private struct CalendarToolbarModifier: ViewModifier {
    let model: CalendarModel

    func body(content: Content) -> some View {
        let unit = model.mode == .week ? "week" : "day"
        content
            .navigationTitle(model.title)
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button { model.goToPrevious() } label: { Image(systemName: "chevron.left") }
                        .help("Previous \(unit)")
                        .accessibilityLabel("Previous \(unit)")
                    Button { model.goToNext() } label: { Image(systemName: "chevron.right") }
                        .help("Next \(unit)")
                        .accessibilityLabel("Next \(unit)")
                    Button { model.goToToday() } label: { Text("Today").padding(.horizontal, Spacing.sm) }
                        .help("Go to today")
                }
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: Binding(get: { model.mode }, set: { model.setMode($0) })) {
                        Text("Week").tag(CalendarMode.week)
                        Text("Day").tag(CalendarMode.day)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .help("Switch between week and day")
                    .accessibilityLabel("View")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {} label: { Image(systemName: "slider.horizontal.3") }
                        .help("Projects and tags")
                        .accessibilityLabel("Projects and tags")
                }
            }
    }
}
