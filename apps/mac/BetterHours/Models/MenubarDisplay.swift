import Foundation

enum MenubarDisplay: String, CaseIterable {
    case current, today

    static let storageKey = "menubarDisplay"

    var title: String {
        switch self {
        case .current: "Current"
        case .today: "Today"
        }
    }

    func labelText(isRunning: Bool, elapsed: TimeInterval, todayTotal: TimeInterval) -> String? {
        switch self {
        case .current:
            return isRunning ? TimeFormat.duration(elapsed) : nil
        case .today:
            return isRunning || todayTotal > 0 ? TimeFormat.duration(todayTotal) : nil
        }
    }
}
