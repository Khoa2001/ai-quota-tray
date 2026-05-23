import SwiftUI

struct TrayContentView: View {

    @EnvironmentObject private var store: QuotaStore
    @State private var showSettings = false
    @State private var refreshRotation: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Provider.allCases) { provider in
                QuotaRow(snapshot: store.snapshots[provider])
                if provider != Provider.allCases.last {
                    Divider()
                }
            }

            Divider()

            HStack(spacing: 14) {
                FooterIconButton(
                    systemName: "arrow.clockwise",
                    help: "Refresh now",
                    disabled: store.isRefreshing
                ) {
                    Task { await store.refresh() }
                }
                .rotationEffect(.degrees(refreshRotation))
                .onChange(of: store.isRefreshing) { refreshing in
                    if refreshing {
                        withAnimation(.linear(duration: 0.7).repeatForever(autoreverses: false)) {
                            refreshRotation = 360
                        }
                    } else {
                        withAnimation(.linear(duration: 0.15)) {
                            refreshRotation = 0
                        }
                    }
                }

                Spacer()

                FooterIconButton(systemName: "gearshape", help: "Settings") {
                    showSettings = true
                }
                FooterIconButton(systemName: "power", help: "Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
        }
        .frame(width: 280)
        .animation(.easeInOut(duration: 0.2), value: store.snapshots.count)
        .task {
            await store.refresh()
            store.startAutoRefresh()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(store)
        }
    }
}

// MARK: - Reusable footer button

private struct FooterIconButton: View {
    let systemName: String
    let help: String
    var disabled: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .imageScale(.medium)
                .foregroundStyle(hovering && !disabled ? Color.primary : Color.secondary)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .onHover { hovering = $0 }
        .help(help)
    }
}
