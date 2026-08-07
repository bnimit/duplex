import SwiftUI
import UniformTypeIdentifiers
import DuplexKit

struct InstanceEditorSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    let existing: Instance?

    private enum IconMode: Hashable {
        case keep, original, badge, custom
    }

    @State private var appURL: URL?
    @State private var name: String = ""
    @State private var badgeColor: BadgeColor = .blue
    // New instances default to an exact copy of the target's icon; the edit flow overrides
    // this to `.keep` in `onAppear` so regenerating doesn't silently change the icon.
    @State private var iconMode: IconMode = .original
    @State private var customIconURL: URL?
    @State private var validationError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(existing == nil ? "New Instance" : "Edit \u{201C}\(existing!.name)\u{201D}")
                .font(.system(size: 15, weight: .semibold))

            section("App") {
                HStack(spacing: 8) {
                    if let appURL {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                            .resizable().frame(width: 22, height: 22)
                    } else {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                    }
                    Text(appURL?.deletingPathExtension().lastPathComponent ?? "No app selected")
                        .foregroundStyle(appURL == nil ? .secondary : .primary)
                    Spacer()
                    Button("Choose App\u{2026}") { pickApp() }.disabled(existing != nil)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05)))
            }

            section("Name") {
                TextField("e.g. Claude Work", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            section("Icon") {
                Picker("Icon", selection: $iconMode) {
                    Text("Original").tag(IconMode.original)
                    if existing != nil {
                        Text("Keep current").tag(IconMode.keep)
                    }
                    Text("Badge").tag(IconMode.badge)
                    Text("Custom").tag(IconMode.custom)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Group {
                    switch iconMode {
                    case .original:
                        Text("An exact copy of the target app's icon, at full resolution.")
                            .font(.caption).foregroundStyle(.secondary)
                    case .keep:
                        Text("The wrapper's current icon will be left unchanged.")
                            .font(.caption).foregroundStyle(.secondary)
                    case .custom:
                        HStack {
                            Text(customIconURL?.lastPathComponent ?? "No image selected")
                                .font(.caption)
                                .foregroundStyle(customIconURL == nil ? .secondary : .primary)
                            Spacer()
                            Button("Choose Image\u{2026}") { pickImage() }
                                .controlSize(.small)
                        }
                    case .badge:
                        HStack(spacing: 10) {
                            ForEach(BadgeColor.allCases) { color in
                                ZStack {
                                    Circle().fill(swatch(color)).frame(width: 22, height: 22)
                                    if badgeColor == color {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .overlay(Circle().stroke(Color.primary.opacity(
                                    badgeColor == color ? 0.35 : 0), lineWidth: 1.5))
                                .onTapGesture { badgeColor = color }
                                .accessibilityLabel(Text(color.rawValue))
                            }
                            Spacer()
                            Text("Drawn over the target app's icon")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
                .frame(minHeight: 24, alignment: .leading)
            }

            if let validationError {
                Label(validationError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(existing == nil ? "Create" : "Save") { submit() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(appURL == nil || name.trimmingCharacters(in: .whitespaces).isEmpty
                              || (iconMode == .custom && customIconURL == nil))
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear {
            if let existing {
                name = existing.name
                appURL = URL(fileURLWithPath: existing.targetPath)
                iconMode = .keep
            }
        }
    }

    @ViewBuilder
    private func section(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .kerning(0.6)
            content()
        }
    }

    private func swatch(_ color: BadgeColor) -> Color {
        switch color {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        }
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            if AppInspector.isElectronBased(url) {
                appURL = url
                validationError = nil
                if name.isEmpty {
                    name = url.deletingPathExtension().lastPathComponent + " 2"
                }
            } else {
                validationError = AppInspectorError.notElectron(url.deletingPathExtension().lastPathComponent)
                    .errorDescription
            }
        }
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .icns, .jpeg, .tiff]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK { customIconURL = panel.url }
    }

    private func submit() {
        guard let appURL else { return }
        let icon: IconChoice
        switch iconMode {
        case .keep: icon = .keepExisting
        case .original: icon = .original
        case .badge: icon = .badge(badgeColor)
        case .custom: icon = .custom(customIconURL!)
        }
        state.create(
            name: name.trimmingCharacters(in: .whitespaces),
            appURL: appURL, icon: icon, existingSlug: existing?.slug)
        // The error alert lives on the parent view, under this sheet, so it would never be
        // seen here — surface the failure inline instead and keep the sheet open.
        if let message = state.errorMessage {
            validationError = message
            state.errorMessage = nil
        } else {
            dismiss()
        }
    }
}
