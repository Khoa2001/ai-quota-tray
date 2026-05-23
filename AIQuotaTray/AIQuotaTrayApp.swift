import SwiftUI

@main
struct AIQuotaTrayApp: App {

    @StateObject private var store = QuotaStore()

    var body: some Scene {
        MenuBarExtra {
            TrayContentView()
                .environmentObject(store)
        } label: {
            Image(systemName: store.traySystemImage)
                .accessibilityLabel("AI Quota Tray")
        }
        .menuBarExtraStyle(.window)
    }
}
