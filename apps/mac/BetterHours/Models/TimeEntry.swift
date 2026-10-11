import Foundation

struct TimeEntry {
    let calendar: Calendar

    private static let suffixes: [(String, Bool)] = [("a.m.", false), ("p.m.", true), ("am", false), ("pm", true), ("a", false), ("p", true)]

    func parse(_ input: String, on day: Date) -> Date? {
        var text = input.lowercased().trimmingCharacters(in: .whitespaces)
        var pm: Bool?
        for (suffix, isPM) in Self.suffixes where text.hasSuffix(suffix) {
            text = String(text.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            pm = isPM
            break
        }
        guard let (hour, minute) = Self.components(text), minute < 60 else { return nil }
        var resolved = hour
        if let pm {
            guard (1...12).contains(hour) else { return nil }
            resolved = hour % 12 + (pm ? 12 : 0)
        }
        guard resolved < 24 else { return nil }
        return calendar.date(bySettingHour: resolved, minute: minute, second: 0, of: day)
    }

    func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = calendar.locale ?? .current
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        return formatter.string(from: date)
    }

    /// Moves to the next or previous multiple of `step` minutes, staying inside the day.
    func step(_ date: Date, up: Bool, minutes step: Int) -> Date {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let current = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let target = up ? (current / step + 1) * step : (current - 1) / step * step
        let clamped = current == 0 && !up ? 0 : min(max(target, 0), 24 * 60 - step)
        return calendar.date(bySettingHour: clamped / 60, minute: clamped % 60, second: 0, of: date) ?? date
    }

    private static func components(_ text: String) -> (Int, Int)? {
        func digits(_ value: Substring) -> Bool { !value.isEmpty && value.allSatisfy { $0.isASCII && $0.isNumber } }
        if let separator = text.firstIndex(where: { $0 == ":" || $0 == "." }) {
            let hour = text[..<separator], minute = text[text.index(after: separator)...]
            guard digits(hour), hour.count <= 2, digits(minute), minute.count == 2 else { return nil }
            return (Int(hour)!, Int(minute)!)
        }
        guard digits(Substring(text)) else { return nil }
        switch text.count {
        case 1, 2: return (Int(text)!, 0)
        case 3: return (Int(text.prefix(1))!, Int(text.suffix(2))!)
        case 4: return (Int(text.prefix(2))!, Int(text.suffix(2))!)
        default: return nil
        }
    }
}
