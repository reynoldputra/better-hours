import AppKit
import BetterHoursCore
import Foundation

struct DemoConfiguration {
    let store: LocalStore
    let clock: @Sendable () -> Date
    let calendar: Calendar
    let selectTitle: String?
    let editorTitle: String?
    let openPopover: Bool
    let reopenWindow: Bool
}

#if DEBUG
extension DemoConfiguration {
    @MainActor
    func apply(to model: CalendarModel) async {
        if ProcessInfo.processInfo.arguments.contains("-demoClose") {
            NSApp.windows.filter(\.canBecomeMain).forEach { $0.close() }
            try? await Task.sleep(for: .seconds(1.5))
            NSLog("demoClose visible after launch check: %d", NSApp.windows.filter { $0.isVisible && $0.canBecomeMain }.count)
        }
        do { try await SampleData.seed(into: store) } catch { return }
        await model.reload()
        if let title = editorTitle, let block = model.blocks.first(where: { $0.title == title }) {
            model.openEditor(id: block.id)
        } else if let title = selectTitle, let block = model.blocks.first(where: { $0.title == title }) {
            model.select(block.id)
        }
        if reopenWindow {
            try? await Task.sleep(for: .seconds(2))
            let visible = { NSApp.windows.filter { $0.isVisible && $0.canBecomeMain }.count }
            NSLog("demoReopen visible before close: %d", visible())
            NSApp.windows.filter(\.canBecomeMain).forEach { $0.close() }
            try? await Task.sleep(for: .seconds(2))
            NSLog("demoReopen visible after close: %d", visible())
            _ = NSApp.delegate?.applicationShouldHandleReopen?(NSApp, hasVisibleWindows: false)
            try? await Task.sleep(for: .seconds(2))
            NSLog("demoReopen visible after reopen: %d", visible())
        }
        if openPopover {
            try? await Task.sleep(for: .seconds(1))
            Self.statusButtons(in: NSApp.windows.compactMap(\.contentView)).first?.performClick(nil)
        }
    }

    private static func statusButtons(in views: [NSView]) -> [NSStatusBarButton] {
        views.flatMap { ($0 as? NSStatusBarButton).map { [$0] } ?? statusButtons(in: $0.subviews) }
    }
}

enum Demo {
    static func configuration(arguments: [String] = ProcessInfo.processInfo.arguments) -> DemoConfiguration? {
        guard arguments.contains("-demo"), let store = try? LocalStore.inMemory() else { return nil }
        let now = SampleData.now
        let began = Date()
        let live = arguments.contains("-demoTick")
        return DemoConfiguration(
            store: store,
            clock: { live ? now.addingTimeInterval(Date().timeIntervalSince(began) * 60) : now },
            calendar: SampleData.calendar,
            selectTitle: arguments.contains("-demoSelect") ? "API schema" : nil,
            editorTitle: arguments.contains("-demoEditor") ? "Design review" : nil,
            openPopover: arguments.contains("-demoPopover"),
            reopenWindow: arguments.contains("-demoReopen")
        )
    }
}
#else
extension DemoConfiguration {
    @MainActor func apply(to model: CalendarModel) async {}
}

enum Demo {
    static func configuration() -> DemoConfiguration? { nil }
}
#endif
