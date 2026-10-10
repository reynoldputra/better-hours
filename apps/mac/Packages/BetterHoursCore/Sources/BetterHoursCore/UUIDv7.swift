import Foundation

public enum UUIDv7 {
    public static func generate(at date: Date = Date()) -> UUID {
        var rng = SystemRandomNumberGenerator()
        return generate(milliseconds: UInt64(max(0, date.timeIntervalSince1970 * 1000)), using: &rng)
    }

    static func generate(milliseconds: UInt64, using rng: inout some RandomNumberGenerator) -> UUID {
        let ms = milliseconds & 0xFFFF_FFFF_FFFF
        let a = UInt64.random(in: .min ... .max, using: &rng)
        let b = UInt64.random(in: .min ... .max, using: &rng)
        let bytes: uuid_t = (
            UInt8(truncatingIfNeeded: ms >> 40),
            UInt8(truncatingIfNeeded: ms >> 32),
            UInt8(truncatingIfNeeded: ms >> 24),
            UInt8(truncatingIfNeeded: ms >> 16),
            UInt8(truncatingIfNeeded: ms >> 8),
            UInt8(truncatingIfNeeded: ms),
            0x70 | (UInt8(truncatingIfNeeded: a >> 8) & 0x0F),
            UInt8(truncatingIfNeeded: a),
            0x80 | (UInt8(truncatingIfNeeded: b >> 56) & 0x3F),
            UInt8(truncatingIfNeeded: b >> 48),
            UInt8(truncatingIfNeeded: b >> 40),
            UInt8(truncatingIfNeeded: b >> 32),
            UInt8(truncatingIfNeeded: b >> 24),
            UInt8(truncatingIfNeeded: b >> 16),
            UInt8(truncatingIfNeeded: b >> 8),
            UInt8(truncatingIfNeeded: b)
        )
        return UUID(uuid: bytes)
    }
}
