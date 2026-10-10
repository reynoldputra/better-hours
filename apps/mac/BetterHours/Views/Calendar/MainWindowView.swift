import SwiftUI

struct MainWindowView: View {
    let calendar: CalendarModel
    let library: LibraryModel
    var scrollHour: Int?

    var body: some View {
        let format = TimeFormat(calendar: calendar.calendar)
        let columns = calendar.columns
        VStack(spacing: 0) {
            if let error = calendar.loadError ?? library.loadError {
                Text(error)
                    .font(Fonts.caption)
                    .foregroundStyle(Theme.danger)
                    .padding(Spacing.sm)
            }
            DayHeaderRow(columns: columns, format: format)
            TimeGrid(
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
    }
}
