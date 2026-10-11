import BetterHoursCore
import AppKit
import SwiftUI

struct TimerPopoverView: View {
    let timer: TimerModel
    let library: LibraryModel
    let calendar: Calendar
    var openMainWindow: () -> Void = {}
    var quit: () -> Void = { NSApp.terminate(nil) }
    @AppStorage private var display: MenubarDisplay

    init(
        timer: TimerModel, library: LibraryModel, calendar: Calendar,
        defaults: UserDefaults = .standard,
        openMainWindow: @escaping () -> Void = {},
        quit: @escaping () -> Void = { NSApp.terminate(nil) }
    ) {
        self.timer = timer
        self.library = library
        self.calendar = calendar
        self.openMainWindow = openMainWindow
        self.quit = quit
        _display = AppStorage(wrappedValue: .current, MenubarDisplay.storageKey, store: defaults)
    }

    var body: some View {
        VStack(spacing: 0) {
            if timer.isRunning {
                runningSection
            } else if let last = timer.lastEnded {
                lastBlockSection(last)
            } else {
                idleSection
            }
            if let error = timer.writeError {
                Divider()
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Text(error).font(Fonts.caption).foregroundStyle(Theme.danger).lineLimit(3)
                    Spacer(minLength: 0)
                    Button { timer.dismissError() } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless)
                        .help("Dismiss")
                        .accessibilityLabel("Dismiss error")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, Spacing.sm)
            }
            Divider()
            HStack {
                Text("Today").foregroundStyle(Theme.muted)
                Spacer()
                Text(TimeFormat.duration(timer.todayTotal)).font(.system(size: 13, weight: .medium, design: .monospaced))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider()
            HStack {
                Text("Show in menubar").foregroundStyle(Theme.muted)
                Spacer()
                Picker("Show in menubar", selection: $display) {
                    ForEach(MenubarDisplay.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Show in menubar")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, Spacing.sm)
            Divider()
            VStack(spacing: 0) {
                MenuRow(title: "Open Better Hours", shortcut: "⌘O", action: openMainWindow)
                    .keyboardShortcut("o")
                MenuRow(title: "Quit", shortcut: "⌘Q", action: quit)
                    .keyboardShortcut("q")
            }
            .padding(Spacing.xs)
        }
        .font(Fonts.body)
        .foregroundStyle(Theme.text)
        .frame(width: 300)
        .background(Theme.background)
    }

    private var runningSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Tracking now").font(Fonts.caption).foregroundStyle(Theme.muted)
                Spacer()
                if let project = library.project(id: timer.running?.projectId) {
                    Text(project.name)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, Spacing.sm)
                        .frame(height: 20)
                        .foregroundStyle(project.color.ink)
                        .background(project.color.fill, in: Capsule())
                }
            }
            RunningTitleField(timer: timer)
            HStack {
                Text(TimeFormat.stopwatch(timer.elapsed))
                    .font(.system(size: 34, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.accent)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Spacer()
                Button { Task { await timer.stop() } } label: { Text("Stop").fontWeight(.semibold).foregroundStyle(Theme.onStrong).padding(.horizontal, Spacing.sm) }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.strong)
                    .help("Stop the timer")
            }
        }
        .controlSize(.large)
        .padding(14)
        .background(Theme.surface)
    }

    private func lastBlockSection(_ last: TimeBlock) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Last block").font(Fonts.caption).foregroundStyle(Theme.muted)
            VStack(alignment: .leading, spacing: 2) {
                Text(last.title.isEmpty ? "Untitled" : last.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text(detail(for: last))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            HStack(spacing: Spacing.sm) {
                Button { Task { await timer.continueLast() } } label: { Text("Continue").fontWeight(.semibold).foregroundStyle(Theme.onAccent).frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .help("Start a new block with the same title and project")
                Button { Task { await timer.start(title: "") } } label: { Text("New").fontWeight(.medium).frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
                    .help("Start an untitled block")
            }
            .controlSize(.large)
            .padding(.top, Spacing.xs)
        }
        .padding(14)
    }

    private var idleSection: some View {
        Button { Task { await timer.start(title: "") } } label: { Text("Start").fontWeight(.semibold).foregroundStyle(Theme.onAccent).frame(maxWidth: .infinity) }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.large)
            .help("Start the timer")
            .padding(14)
    }

    private func detail(for block: TimeBlock) -> String {
        let project = library.project(id: block.projectId)?.name ?? "No project"
        guard let end = block.endAt else { return project }
        return "\(project) · ended \(TimeFormat(calendar: calendar).clockTime(end))"
    }
}

private struct MenuRow: View {
    let title: String
    let shortcut: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Text(shortcut).font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowStyle())
    }
}

private struct MenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration)
    }

    private struct Row: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: Radius.control)
                        .fill(configuration.isPressed ? Theme.line : hovering ? Theme.sunken : .clear)
                )
                .overlay(RoundedRectangle(cornerRadius: Radius.control).stroke(Theme.accent, lineWidth: focused ? 2 : 0))
                .onHover { hovering = $0 }
        }
    }
}
