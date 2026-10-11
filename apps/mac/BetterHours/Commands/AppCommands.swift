import SwiftUI

struct AppCommands: Commands {
    let calendar: CalendarModel
    let timer: TimerModel
    let typing: TextEditingTracker
    let opener: WindowOpener
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Block") {
                opener.show()
                Task { await calendar.newBlock() }
            }
            .keyboardShortcut("n")
        }
        CommandGroup(before: .toolbar) {
            let unit = calendar.mode == .week ? "Week" : "Day"
            Button("Today") { calendar.goToToday() }
                .keyboardShortcut("t")
            Button("Previous \(unit)") { calendar.goToPrevious() }
                .keyboardShortcut(.leftArrow)
                .disabled(typing.isEditing)
            Button("Next \(unit)") { calendar.goToNext() }
                .keyboardShortcut(.rightArrow)
                .disabled(typing.isEditing)
            Divider()
            Button("Week") { calendar.setMode(.week) }
                .keyboardShortcut("1")
            Button("Day") { calendar.setMode(.day) }
                .keyboardShortcut("2")
            Divider()
        }
        CommandGroup(after: .windowArrangement) {
            Button("Projects and Tags") { openWindow(id: "library") }
                .keyboardShortcut("p", modifiers: [.command, .shift])
        }
        CommandMenu("Timer") {
            Button(timer.isRunning ? "Stop Timer" : "Start Timer") { Task { await timer.toggle() } }
                .keyboardShortcut(.return)
        }
    }
}
