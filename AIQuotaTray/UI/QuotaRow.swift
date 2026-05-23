import SwiftUI

struct QuotaRow: View {

    let snapshot: QuotaSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let snap = snapshot {
                content(for: snap)
                    .transition(.opacity)
            } else {
                loadingRow
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .animation(.easeInOut(duration: 0.25), value: snapshot?.used)
        .animation(.easeInOut(duration: 0.25), value: snapshot?.error)
    }

    // MARK: - States

    private var loadingRow: some View {
        HStack {
            Text("—").font(.caption2).foregroundStyle(.tertiary)
            Spacer()
            ProgressView().controlSize(.mini)
        }
    }

    @ViewBuilder
    private func content(for snap: QuotaSnapshot) -> some View {
        // Row 1: name + usage / error
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(snap.provider.rawValue)
                .font(.system(.callout, design: .default, weight: .semibold))

            Spacer()

            if let error = snap.error {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            } else {
                Text(usageText(snap))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }

        // Row 2: progress bar (only when cap known)
        if snap.error == nil, let fraction = snap.fraction {
            ProgressView(value: fraction)
                .tint(barColor(fraction))
                .scaleEffect(x: 1, y: 0.55, anchor: .center)
                .padding(.vertical, -1)
                .animation(.easeInOut(duration: 0.4), value: fraction)
        }

        // Row 3: reset label
        if snap.error == nil, let resets = snap.resetsAt {
            Text(resetLabel(snap.provider, resets))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    // MARK: - Formatting

    private func usageText(_ snap: QuotaSnapshot) -> String {
        if snap.unit == "%" {
            return String(format: "%.0f%%", snap.used)
        }
        if snap.unit.hasSuffix("plan") {
            return snap.unit
        }
        let u = format(snap.used, unit: snap.unit)
        if let cap = snap.cap {
            return "\(u) / \(format(cap, unit: snap.unit))"
        }
        return u
    }

    private func format(_ value: Double, unit: String) -> String {
        switch unit {
        case "tokens":
            if value >= 1_000_000 { return String(format: "%.1fM tok", value / 1_000_000) }
            if value >= 1_000     { return String(format: "%.0fK tok", value / 1_000) }
            return "\(Int(value)) tok"
        case "req":
            return "\(Int(value)) req"
        default:
            return "\(Int(value)) \(unit)"
        }
    }

    private func resetLabel(_ provider: Provider, _ date: Date) -> String {
        let diff = date.timeIntervalSinceNow

        if provider == .cursor {
            let fmt = DateFormatter()
            fmt.dateFormat = "MMM d"
            return "resets \(fmt.string(from: date))"
        }

        guard diff > 0 else { return "window reset" }

        let totalHours = diff / 3600
        if totalHours >= 24 {
            let d = Int(totalHours / 24)
            let h = Int(totalHours.truncatingRemainder(dividingBy: 24))
            return h > 0 ? "resets in \(d)d \(h)h" : "resets in \(d)d"
        }
        let h = Int(diff / 3600)
        let m = Int(diff.truncatingRemainder(dividingBy: 3600) / 60)
        return h > 0 ? "resets in \(h)h \(m)m" : "resets in \(m)m"
    }

    private func barColor(_ fraction: Double) -> Color {
        if fraction < 0.60 { return .green }
        if fraction < 0.85 { return .orange }
        return .red
    }
}
