import BetterHoursCore
import Foundation

struct DemoConfiguration {
    let store: LocalStore
    let clock: @Sendable () -> Date
    let calendar: Calendar
    let selectTitle: String?
    let editorTitle: String?
}

#if DEBUG
extension DemoConfiguration {
    @MainActor
    func apply(to model: CalendarModel) async {
        do { try await SampleData.seed(into: store) } catch { return }
        await model.reload()
        if let title = editorTitle, let block = model.blocks.first(where: { $0.title == title }) {
            model.openEditor(id: block.id)
        } else if let title = selectTitle, let block = model.blocks.first(where: { $0.title == title }) {
            model.select(block.id)
        }
    }
}

enum Demo {
    static func configuration(arguments: [String] = ProcessInfo.processInfo.arguments) -> DemoConfiguration? {
        guard arguments.contains("-demo"), let store = try? LocalStore.inMemory() else { return nil }
        let now = SampleData.now
        return DemoConfiguration(
            store: store,
            clock: { now },
            calendar: SampleData.calendar,
            selectTitle: arguments.contains("-demoSelect") ? "API schema" : nil,
            editorTitle: arguments.contains("-demoEditor") ? "Design review" : nil
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
