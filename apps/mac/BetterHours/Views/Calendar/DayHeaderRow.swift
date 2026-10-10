import SwiftUI

struct DayHeaderRow: View {
    let columns: [DayColumn]
    let format: TimeFormat

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: Metrics.gutterWidth)
            ForEach(columns) { column in
                header(column)
            }
        }
        .frame(height: Metrics.dayHeaderHeight)
        .overlay(alignment: .bottom) {
            Theme.line.frame(height: 1)
        }
    }

    private func header(_ column: DayColumn) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(format.dayName(column.start))
                .font(.system(size: 13, weight: column.isToday ? .bold : .semibold))
                .foregroundStyle(column.isToday ? Theme.accentText : column.isWeekend ? Theme.muted : Theme.text)
            Text(TimeFormat.duration(column.total))
                .font(Fonts.mono)
                .foregroundStyle(column.isToday ? Theme.accentText : Theme.muted)
        }
        .padding(.horizontal, Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(column.isToday ? Theme.accentSoft : Color.clear)
        .overlay(alignment: .leading) { Theme.line.frame(width: 1) }
        .overlay(alignment: .bottom) {
            if column.isToday { Theme.accent.frame(height: 2) }
        }
    }
}
