import SwiftUI
import DuplexKit

struct LicenseSheet: View {
    @EnvironmentObject var license: LicenseManager
    @Environment(\.dismiss) private var dismiss
    @State private var keyInput = ""
    @State private var working = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch license.state {
            case .licensed(let suffix, let activatedAt):
                headerRow(icon: "checkmark.seal.fill", tint: DuplexTheme.indigo,
                          title: "Duplex is licensed",
                          subtitle: "Key ending in \u{2026}\(suffix), activated \(activatedAt.formatted(date: .abbreviated, time: .omitted)) on this Mac.")
                if let errorText {
                    Label(errorText, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.red)
                }
                HStack {
                    Button("Deactivate This Mac", role: .destructive) {
                        Task { await deactivate() }
                    }.disabled(working)
                    Spacer()
                    Button("Done") { dismiss() }
                        .modifier(ProminentActionStyle())
                        .keyboardShortcut(.defaultAction)
                }
            case .free:
                headerRow(icon: "sparkles", tint: DuplexTheme.coral,
                          title: "Unlock unlimited instances",
                          subtitle: "Your first instance is free forever. A $5 license unlocks unlimited instances on up to 3 Macs.")
                TextField("License key (from your purchase email)", text: $keyInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                if let errorText {
                    Label(errorText, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.red)
                }
                Text("Privacy: only the key and this Mac's name are sent to the license server, and only when you activate or Duplex revalidates.")
                    .font(.caption2).foregroundStyle(.tertiary)
                HStack {
                    Link("Buy for $5", destination: DuplexConfig.checkoutURL)
                    Spacer()
                    Button("Cancel") { dismiss() }
                    Button(working ? "Activating\u{2026}" : "Activate") {
                        Task { await activate() }
                    }
                    .modifier(ProminentActionStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(working || keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func headerRow(icon: String, tint: Color, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(tint.opacity(0.15)).frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func activate() async {
        working = true
        defer { working = false }
        do {
            try await license.activate(key: keyInput)
            errorText = nil
        } catch let clientError as LicenseClientError {
            if case .keyInvalid(let message) = clientError {
                errorText = message + " If you have hit your activation limit, open Duplex on another Mac, choose License… from the app menu, and click Deactivate This Mac, then try again here."
            } else {
                errorText = clientError.localizedDescription
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func deactivate() async {
        working = true
        defer { working = false }
        do {
            try await license.deactivate()
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
