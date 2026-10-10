import BetterHoursCore
import Foundation

enum SampleData {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        calendar.locale = Locale(identifier: "en_GB")
        calendar.firstWeekday = 2
        return calendar
    }()

    static func date(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 10, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    static let now = date(8, 12, 24)

    @MainActor
    static func seeded() async throws -> LocalStore {
        let store = try LocalStore.inMemory()
        let website = Project(name: "Website", color: .blue)
        let backend = Project(name: "Backend", color: .orange)
        let writing = Project(name: "Writing", color: .purple)
        let clients = Project(name: "Clients", color: .pink)
        let admin = Project(name: "Admin", color: .teal)
        for project in [website, backend, writing, clients, admin] { try await store.save(project) }

        let blocks: [(String, Project, Date, Date?)] = [
            ("Design review", website, date(5, 9), date(5, 10, 30)),
            ("Client call", clients, date(5, 13), date(5, 14)),
            ("Admin", admin, date(5, 15), date(5, 16)),
            ("API schema", backend, date(6, 9, 30), date(6, 12)),
            ("Docs", writing, date(6, 13, 30), date(6, 15)),
            ("Code review", backend, date(7, 10), date(7, 11)),
            ("Email", admin, date(7, 10, 30), date(7, 11, 30)),
            ("Design system", website, date(7, 13), date(7, 16)),
            ("Standup", clients, date(8, 9), date(8, 9, 30)),
            ("Build editor", backend, date(8, 11), nil),
        ]
        for (title, project, start, end) in blocks {
            try await store.save(TimeBlock(title: title, projectId: project.id, startAt: start, endAt: end))
        }
        return store
    }
}
