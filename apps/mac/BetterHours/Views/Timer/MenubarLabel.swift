import SwiftUI

struct MenubarLabel: View {
    let timer: TimerModel
    @AppStorage private var display: MenubarDisplay

    init(timer: TimerModel, defaults: UserDefaults = .standard) {
        self.timer = timer
        _display = AppStorage(wrappedValue: .current, MenubarDisplay.storageKey, store: defaults)
    }

    private var text: String? {
        display.labelText(isRunning: timer.isRunning, elapsed: timer.elapsed, todayTotal: timer.todayTotal)
    }

    var body: some View {
        HStack(spacing: 6) {
            Image("MenubarGlyph")
            if let text {
                Text(text)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility)
        .help("Better Hours")
    }

    private var accessibility: String {
        guard let text else { return "Better Hours" }
        return timer.isRunning && display == .current ? "Better Hours, tracking \(text)" : "Better Hours, \(text)"
    }
}
