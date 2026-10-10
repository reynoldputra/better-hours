import Foundation

public func snap(_ date: Date, toMinutes step: Int, calendar: Calendar) -> Date {
    guard step > 0 else { return date }
    let parts = calendar.dateComponents([.minute, .second, .nanosecond], from: date)
    let intoHour = Double(parts.minute ?? 0) * 60 + Double(parts.second ?? 0) + Double(parts.nanosecond ?? 0) / 1e9
    let stepSeconds = Double(step) * 60
    let snapped = (intoHour / stepSeconds + 0.5).rounded(.down) * stepSeconds
    return date.addingTimeInterval(snapped - intoHour)
}
