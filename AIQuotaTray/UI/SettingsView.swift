import SwiftUI
import ServiceManagement

struct SettingsView: View {

    @AppStorage("refreshInterval") private var refreshInterval: Int = 60
    @EnvironmentObject private var store: QuotaStore
    @Environment(\.dismiss) private var dismiss

    @State private var launchAtLogin = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.headline)

            GroupBox("Refresh interval") {
                Picker("Interval", selection: $refreshInterval) {
                    Text("30 s").tag(30)
                    Text("1 min").tag(60)
                    Text("2 min").tag(120)
                    Text("5 min").tag(300)
                }
                .pickerStyle(.segmented)
                .onChange(of: refreshInterval) { _, _ in
                    store.startAutoRefresh()
                }
                .padding(.vertical, 2)
            }

            GroupBox("System") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        toggleLaunchAtLogin(enabled)
                    }
                    .padding(.vertical, 2)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 300)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func toggleLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else        { try SMAppService.mainApp.unregister() }
        } catch {
            // Silently ignore — fails for unsigned / un-notarized apps.
        }
    }
}
