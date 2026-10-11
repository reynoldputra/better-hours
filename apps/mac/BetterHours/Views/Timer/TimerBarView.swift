import BetterHoursCore
import SwiftUI

struct TimerBarView: View {
    let timer: TimerModel
    let library: LibraryModel

    var body: some View {
        HStack(spacing: Spacing.md) {
            if timer.isRunning {
                RunningTitleField(timer: timer)
                ProjectMenu(timer: timer, library: library)
            } else {
                TextField("What are you working on?", text: Binding(get: { timer.draftTitle }, set: { timer.draftTitle = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .accessibilityLabel("Timer title")
                    .onSubmit { Task { await timer.startFromDraft() } }
            }
            Text(TimeFormat.stopwatch(timer.elapsed))
                .font(.system(size: 20, weight: .medium, design: .monospaced))
                .foregroundStyle(timer.isRunning ? Theme.accent : Theme.muted)
                .accessibilityLabel("Elapsed time")
            if timer.isRunning {
                Button { Task { await timer.stop() } } label: { Text("Stop").fontWeight(.semibold).foregroundStyle(Theme.onStrong).padding(.horizontal, Spacing.xs) }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.strong)
                    .help("Stop the timer (⌘Return)")
            } else {
                Button { Task { await timer.startFromDraft() } } label: { Text("Start").fontWeight(.semibold).foregroundStyle(Theme.onAccent).padding(.horizontal, Spacing.xs) }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .help("Start the timer (⌘Return)")
            }
            Divider().frame(height: 28)
            total("Today", timer.todayTotal)
            total("This week", timer.weekTotal)
        }
        .controlSize(.large)
        .padding(.horizontal, Spacing.lg)
        .frame(height: 56)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private func total(_ label: String, _ value: TimeInterval) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(label).font(Fonts.caption).foregroundStyle(Theme.muted)
            Text(TimeFormat.duration(value)).font(Fonts.monoMedium)
        }
        .accessibilityElement(children: .combine)
    }
}

struct ProjectMenu: View {
    let timer: TimerModel
    let library: LibraryModel

    var body: some View {
        Picker("Project", selection: Binding<UUID?>(
            get: { timer.running?.projectId },
            set: { id in Task { await timer.setRunningProject(id) } }
        )) {
            Text("No project").tag(UUID?.none)
            if !library.projects.isEmpty { Divider() }
            ForEach(library.projects) { project in
                Label { Text(project.name) } icon: { ProjectDot.image(project.color) }
                    .tag(UUID?.some(project.id))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: 170)
        .help("Project of the running block")
        .accessibilityLabel("Project")
    }
}
