import Foundation
import Testing
@testable import BetterHoursCore

struct PureFunctionTests {
    @Test func snapRejectsNonPositiveStep() {
        let date = Date(timeIntervalSince1970: 1_000_000.5)
        #expect(snap(date, toMinutes: 0, calendar: Calendar(identifier: .gregorian)) == date)
    }

    @Test func totalIgnoresInvertedClip() {
        let t = Date(timeIntervalSince1970: 1_000_000)
        let block = TimeBlock(startAt: t, endAt: t.addingTimeInterval(60))
        let interval = DateInterval(start: t.addingTimeInterval(120), end: t.addingTimeInterval(180))
        #expect(total(of: [block], in: interval, now: t) == 0)
    }

    @Test func runningBlockBeforeNowIsNotNegative() {
        let t = Date(timeIntervalSince1970: 1_000_000)
        let block = TimeBlock(startAt: t.addingTimeInterval(60), endAt: nil)
        #expect(total(of: [block], in: DateInterval(start: t, end: t.addingTimeInterval(600)), now: t) == 0)
    }
}
