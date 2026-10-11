import AppKit
import SwiftUI

struct SettingsView: View {
    let model: LaunchAtLogin

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(get: { model.isOn }, set: { model.set($0) }))
                if let message = model.message {
                    Text(message).font(Fonts.caption).foregroundStyle(Theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refresh() }
    }
}
