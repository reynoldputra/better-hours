import Foundation
import Testing
@testable import BetterHoursCore

struct FixtureTests {
    struct TotalsInput: Decodable {
        var now: String
        var interval: Fixtures.Interval
        var blocks: [Fixtures.Block]
    }

    @Test func totalsFixtures() throws {
        let cases = try Fixtures.load("totals", input: TotalsInput.self, expected: Double.self)
        #expect(!cases.isEmpty)
        for c in cases {
            let start = try Fixtures.date(c.input.interval.start)
            let end = try Fixtures.date(c.input.interval.end)
            let result = total(
                of: try c.input.blocks.map(Fixtures.timeBlock),
                in: DateInterval(start: start, end: end),
                now: try Fixtures.date(c.input.now))
            #expect(abs(result - c.expected) < 0.0005, "\(c.name): got \(result), expected \(c.expected)")
        }
    }

    struct SlotJSON: Decodable { var index: Int; var count: Int }
    struct LayoutInput: Decodable {
        var now: String
        var blocks: [Fixtures.Block]
    }

    @Test func overlapLayoutFixtures() throws {
        let cases = try Fixtures.load("overlap-layout", input: LayoutInput.self, expected: [String: SlotJSON].self)
        #expect(!cases.isEmpty)
        for c in cases {
            let result = layoutColumns(
                for: try c.input.blocks.map(Fixtures.timeBlock),
                now: try Fixtures.date(c.input.now))
            let expected = Dictionary(uniqueKeysWithValues: c.expected.map {
                (Fixtures.uuid(forShortId: $0.key), ColumnSlot(index: $0.value.index, count: $0.value.count))
            })
            #expect(result == expected, "\(c.name)")
        }
    }

    struct SnapInput: Decodable {
        var date: String
        var step: Int
        var timeZone: String
    }

    @Test func snapFixtures() throws {
        let cases = try Fixtures.load("snap", input: SnapInput.self, expected: String.self)
        #expect(!cases.isEmpty)
        for c in cases {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try #require(TimeZone(identifier: c.input.timeZone))
            let result = snap(try Fixtures.date(c.input.date), toMinutes: c.input.step, calendar: calendar)
            let expected = try Fixtures.date(c.expected)
            #expect(abs(result.timeIntervalSince(expected)) < 0.0005, "\(c.name)")
        }
    }
}
