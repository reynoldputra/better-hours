import AppKit
import SwiftUI

struct WhenRow: View {
    @Binding var draft: EditorDraft
    let calendar: Calendar
    let now: Date

    private var entry: TimeEntry { TimeEntry(calendar: calendar) }
    private var endsOnAnotherDay: Bool {
        draft.endAt.map { !calendar.isDate($0, inSameDayAs: draft.startAt) } ?? false
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.sm) { startGroup; endGroup; duration }
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) { startGroup; Spacer(); duration }
                HStack(spacing: Spacing.sm) { Text("to").foregroundStyle(Theme.muted); endGroup }
            }
        }
    }

    private var startGroup: some View {
        HStack(spacing: Spacing.sm) {
            DateButton(date: draft.startAt, calendar: calendar, label: "Start date") { shiftDays(to: $0) }
            TimeField(value: draft.startAt, entry: entry, label: "Start time") { draft.startAt = $0 }
        }
    }

    @ViewBuilder
    private var endGroup: some View {
        Text("–").foregroundStyle(Theme.muted)
        if let end = draft.endAt {
            HStack(spacing: Spacing.sm) {
                if endsOnAnotherDay {
                    DateButton(date: end, calendar: calendar, label: "End date") { setEndDay($0, of: end) }
                }
                TimeField(value: end, entry: entry, label: "End time") { draft.endAt = $0 }
            }
        } else {
            Text("Running")
                .foregroundStyle(Theme.accentText)
                .font(Fonts.bodySemibold)
                .accessibilityLabel("End: running")
        }
    }

    private var duration: some View {
        let value = TimeFormat.duration(draft.duration(now: now))
        return Text(value)
            .font(Fonts.monoMedium)
            .foregroundStyle(Theme.muted)
            .lineLimit(1)
            .fixedSize()
            .accessibilityLabel("Duration \(value)")
    }

    private func shiftDays(to day: Date) {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: draft.startAt), to: calendar.startOfDay(for: day)).day ?? 0
        guard days != 0 else { return }
        draft.startAt = calendar.date(byAdding: .day, value: days, to: draft.startAt) ?? draft.startAt
        draft.endAt = draft.endAt.flatMap { calendar.date(byAdding: .day, value: days, to: $0) }
    }

    private func setEndDay(_ day: Date, of end: Date) {
        let time = calendar.dateComponents([.hour, .minute], from: end)
        draft.endAt = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: day) ?? end
    }
}

private struct DateButton: View {
    let date: Date
    let calendar: Calendar
    let label: String
    let onPick: (Date) -> Void
    @State private var open = false

    var body: some View {
        Button { open = true } label: { Text(title).fixedSize() }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .help(label)
            .accessibilityLabel("\(label), \(title)")
            .popover(isPresented: $open, arrowEdge: .bottom) {
                DatePicker(label, selection: Binding(get: { date }, set: onPick), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .environment(\.calendar, calendar)
                    .environment(\.timeZone, calendar.timeZone)
                    .padding(Spacing.md)
            }
    }

    private var title: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = calendar.locale ?? .current
        formatter.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return formatter.string(from: date)
    }
}

private struct TimeField: View {
    let value: Date
    let entry: TimeEntry
    let label: String
    let onCommit: (Date) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(label, text: $text)
            .textFieldStyle(.roundedBorder)
            .controlSize(.large)
            .font(.system(size: 13, design: .monospaced))
            .multilineTextAlignment(.center)
            .frame(width: 68)
            .focused($focused)
            .help("\(label). Up and down arrows change it by 5 minutes.")
            .accessibilityLabel(label)
            .onSubmit(commit)
            .onKeyPress(.upArrow) { nudge(up: true) }
            .onKeyPress(.downArrow) { nudge(up: false) }
            .onChange(of: focused) { _, isFocused in
                if isFocused {
                    Task { @MainActor in NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }
                } else {
                    commit()
                }
            }
            .onChange(of: value, initial: true) { _, new in
                if !focused { text = entry.format(new) }
            }
    }

    private func commit() {
        let parsed = entry.parse(text, on: value)
        if let parsed, parsed != value { onCommit(parsed) }
        text = entry.format(parsed ?? value)
    }

    private func nudge(up: Bool) -> KeyPress.Result {
        let base = entry.parse(text, on: value) ?? value
        let next = entry.step(base, up: up, minutes: BlockRules.snapMinutes)
        text = entry.format(next)
        if next != value { onCommit(next) }
        return .handled
    }
}
