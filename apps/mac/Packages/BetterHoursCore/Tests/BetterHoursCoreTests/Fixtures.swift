import Foundation
@testable import BetterHoursCore

enum Fixtures {
    struct Interval: Decodable { var start: String; var end: String }
    struct Block: Decodable { var id: String; var startAt: String; var endAt: String? }
    struct File<Input: Decodable, Expected: Decodable>: Decodable {
        struct Case: Decodable { var name: String; var input: Input; var expected: Expected }
        var cases: [Case]
    }

    static func load<I: Decodable, E: Decodable>(_ name: String, input: I.Type, expected: E.Type, filePath: String = #filePath) throws -> [File<I, E>.Case] {
        var dir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        while dir.path != "/" {
            let candidate = dir.appendingPathComponent("fixtures/\(name).json")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try JSONDecoder().decode(File<I, E>.self, from: Data(contentsOf: candidate)).cases
            }
            dir.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }

    static func date(_ text: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: text) else { throw CocoaError(.formatting) }
        return date
    }

    static func uuid(forShortId id: String) -> UUID {
        precondition(id.utf8.count <= 16, "fixture id \(id) is longer than 16 bytes")
        var bytes = [UInt8](repeating: 0, count: 16)
        for (i, byte) in id.utf8.prefix(16).enumerated() { bytes[i] = byte }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    static func timeBlock(_ block: Block) throws -> TimeBlock {
        TimeBlock(
            id: uuid(forShortId: block.id),
            startAt: try date(block.startAt),
            endAt: try block.endAt.map(date))
    }
}
