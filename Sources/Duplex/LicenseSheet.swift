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
                Text("Duplex is licensed").font(.title3).bold()
                Text("Key ending in \u{2026}\(suffix), activated \(activatedAt.formatted(date: .abbreviated, time: .omitted)) on this Mac.")
                    .font(.callout).foregroundStyle(.secondary)
                if let errorText {
                    Text(errorText).font(.caption).foregroundStyle(.red)
                }
                HStack {
                    Button("Deactivate This Mac", role: .destructive) {
                        Task { await deactivate() }
                    }.disabled(working)
                    Spacer()
                    Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
                }
            case .free:
                Text("Unlock unlimited instances").font(.title3).bold()
                Text("Your first instance is free forever. A $5 license unlocks unlimited instances on up to 3 Macs.")
                    .font(.callout).foregroundStyle(.secondary)
                TextField("License key (from your purchase email)", text: $keyInput)
                    .textFieldStyle(.roundedBorder)
                if let errorText {
                    Text(errorText).font(.caption).foregroundStyle(.red)
                }
                Text("Privacy: only the key itself is sent to the license server, and only when you activate or Duplex revalidates.")
                    .font(.caption2).foregroundStyle(.secondary)
                HStack {
                    Link("Buy for $5", destination: DuplexConfig.checkoutURL)
                    Spacer()
                    Button("Cancel") { dismiss() }
                    Button(working ? "Activating\u{2026}" : "Activate") {
                        Task { await activate() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(working || keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func activate() async {
        working = true
        defer { working = false }
        do {
            try await license.activate(key: keyInput)
            errorText = nil
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
