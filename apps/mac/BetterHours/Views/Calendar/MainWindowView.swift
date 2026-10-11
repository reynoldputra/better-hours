import SwiftUI

struct MainWindowView: View {
    let calendar: CalendarModel
    let library: LibraryModel
    let timer: TimerModel
    var scrollHour: Int?

    var body: some View {
        let format = TimeFormat(calendar: calendar.calendar)
        let columns = calendar.columns
        VStack(spacing: 0) {
            TimerBarView(timer: timer, library: library)
            if let error = calendar.loadError ?? library.loadError {
                Text(error)
                    .font(Fonts.caption)
                    .foregroundStyle(Theme.danger)
                    .padding(Spacing.sm)
            }
            DayHeaderRow(columns: columns, format: format)
            TimeGrid(
                model: calendar,
                columns: columns,
                library: library,
                format: format,
                now: calendar.now,
                scrollHour: scrollHour ?? calendar.initialScrollHour
            )
        }
        .font(Fonts.body)
        .foregroundStyle(Theme.text)
        .background(Theme.background)
        .calendarToolbar(calendar)
        .confirmationDialog(
            "Delete this block?",
            isPresented: Binding(get: { calendar.pendingDeleteId != nil }, set: { if !$0 { calendar.pendingDeleteId = nil } }),
            titleVisibility: .visible,
            presenting: calendar.pendingDeleteId
        ) { id in
            Button("Delete", role: .destructive) { Task { await calendar.deleteBlock(id: id) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This cannot be undone.")
        }
        .alert(
            "Better Hours could not save",
            isPresented: Binding(get: { calendar.writeError != nil }, set: { if !$0 { calendar.writeError = nil } })
        ) {
            Button("OK") {}
        } message: {
            Text(calendar.writeError ?? "")
        }
        .alert(
            "Better Hours could not save",
            isPresented: Binding(get: { timer.writeError != nil }, set: { if !$0 { timer.dismissError() } })
        ) {
            Button("OK") {}
        } message: {
            Text(timer.writeError ?? "")
        }
    }
}
