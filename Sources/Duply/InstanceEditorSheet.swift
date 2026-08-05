import SwiftUI
import UniformTypeIdentifiers
import DuplyKit

struct InstanceEditorSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    let existing: Instance?

    @State private var appURL: URL?
    @State private var name: String = ""
    @State private var badgeColor: BadgeColor = .blue
    @State private var useCustomIcon = false
    @State private var customIconURL: URL?
    @State private var validationError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(existing == nil ? "New Instance" : "Edit “\(existing!.name)”")
                .font(.title3).bold()

            HStack {
                Text(appURL?.lastPathComponent ?? "No app selected")
                    .foregroundStyle(appURL == nil ? .secondary : .primary)
                Spacer()
                Button("Choose App…") { pickApp() }.disabled(existing != nil)
            }

            TextField("Instance name (e.g. Claude Work)", text: $name)
                .textFieldStyle(.roundedBorder)

            Picker("Icon", selection: $useCustomIcon) {
                Text("Colored badge").tag(false)
                Text("Custom image").tag(true)
            }
            .pickerStyle(.segmented)

            if useCustomIcon {
                HStack {
                    Text(customIconURL?.lastPathComponent ?? "No image selected")
                        .foregroundStyle(customIconURL == nil ? .secondary : .primary)
                    Spacer()
                    Button("Choose Image…") { pickImage() }
                }
            } else {
                HStack(spacing: 8) {
                    ForEach(BadgeColor.allCases) { color in
                        Circle()
                            .fill(swatch(color))
                            .frame(width: 22, height: 22)
                            .overlay(Circle().stroke(.primary, lineWidth: badgeColor == color ? 2 : 0))
                            .onTapGesture { badgeColor = color }
                    }
                }
            }

            if let validationError {
                Text(validationError).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(existing == nil ? "Create" : "Save") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(appURL == nil || name.trimmingCharacters(in: .whitespaces).isEmpty
                              || (useCustomIcon && customIconURL == nil))
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear {
            if let existing {
                name = existing.name
                appURL = URL(fileURLWithPath: existing.targetPath)
            }
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
        let icon: IconChoice = useCustomIcon ? .custom(customIconURL!) : .badge(badgeColor)
        state.create(
            name: name.trimmingCharacters(in: .whitespaces),
            appURL: appURL, icon: icon, existingSlug: existing?.slug)
        if state.errorMessage == nil { dismiss() }
    }
}
