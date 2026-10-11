import SwiftUI

struct MenubarLabel: View {
    let timer: TimerModel

    var body: some View {
        HStack(spacing: 6) {
            Image("MenubarGlyph")
            if timer.isRunning {
                Text(TimeFormat.duration(timer.elapsed))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(timer.isRunning ? "Better Hours, tracking \(TimeFormat.duration(timer.elapsed))" : "Better Hours")
        .help("Better Hours")
    }
}
