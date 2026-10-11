import Foundation

struct TimeFormat {
    private let clock: DateFormatter
    private let weekday: DateFormatter
    private let calendar: Calendar

    init(calendar: Calendar) {
        func make(_ template: String) -> DateFormatter {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.locale = calendar.locale ?? .current
            formatter.setLocalizedDateFormatFromTemplate(template)
            return formatter
        }
        self.calendar = calendar
        clock = make("jmm")
        weekday = make("EEEd")
    }

    func clockTime(_ date: Date) -> String { clock.string(from: date) }
    func hourLabel(_ hour: Int, on day: Date) -> String {
        clockTime(calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day)
    }

    func dayName(_ date: Date) -> String { weekday.string(from: date) }

    static func duration(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int(interval / 60))
        return "\(minutes / 60):" + String(format: "%02d", minutes % 60)
    }

    static func stopwatch(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        return "\(seconds / 3600):" + String(format: "%02d:%02d", seconds / 60 % 60, seconds % 60)
    }
}
