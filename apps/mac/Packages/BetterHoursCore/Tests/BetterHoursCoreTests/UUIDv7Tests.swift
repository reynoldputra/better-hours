import Foundation
import Testing
@testable import BetterHoursCore

struct UUIDv7Tests {
    @Test func versionAndVariantBits() {
        for _ in 0..<100 {
            let bytes = UUIDv7.generate().uuid
            #expect(bytes.6 >> 4 == 0x7)
            #expect(bytes.8 >> 6 == 0b10)
        }
    }

    @Test func embedsMillisecondTimestamp() {
        let date = Date(timeIntervalSince1970: 1_791_450_000.123)
        let bytes = UUIDv7.generate(at: date).uuid
        var ms: UInt64 = 0
        for byte in [bytes.0, bytes.1, bytes.2, bytes.3, bytes.4, bytes.5] { ms = ms << 8 | UInt64(byte) }
        #expect(ms == 1_791_450_000_123)
    }

    @Test func sortsByTimeAndIsUnique() {
        let early = UUIDv7.generate(at: Date(timeIntervalSince1970: 1_000_000))
        let late = UUIDv7.generate(at: Date(timeIntervalSince1970: 2_000_000))
        #expect(early.uuidString < late.uuidString)
        #expect(Set((0..<1000).map { _ in UUIDv7.generate() }).count == 1000)
    }
}
