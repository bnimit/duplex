import AppKit
import SwiftUI
import DuplexKit

struct InstanceListView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var license: LicenseManager
    @State private var editorTarget: EditorTarget?
    @State private var deleteCandidate: Instance?

    enum EditorTarget: Identifiable {
        case new
        case edit(Instance)
        var id: String {
            switch self {
            case .new: return "new"
            case .edit(let i): return i.slug
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if state.instances.isEmpty {
                // Not ContentUnavailableView: that's macOS 14+, our floor is 13.
                VStack(spacing: 8) {
                    Image(systemName: "square.on.square.dashed")
                        .font(.system(size: 40)).foregroundStyle(.secondary)
                    Text("No instances yet").font(.title3).bold()
                    Text("Create a wrapper to run a second copy of an Electron app — like a second Claude with its own login.")
                        .font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).frame(maxWidth: 380)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(state.instances) { instance in
                    row(instance)
                }
            }
            Divider()
            HStack {
                licenseStatus
                Spacer()
                Button("New Instance…") {
                    if state.canCreateNewInstance {
                        editorTarget = .new
                    } else {
                        state.showLicenseSheet = true
                    }
                }
                .keyboardShortcut("n")
                .help("Wrappers are saved to \(state.outputDir.path)")
            }
            .padding(10)
        }
        .sheet(item: $editorTarget) { target in
            switch target {
            case .new: InstanceEditorSheet(existing: nil)
            case .edit(let instance): InstanceEditorSheet(existing: instance)
            }
        }
        .sheet(isPresented: $state.showLicenseSheet) {
            LicenseSheet()
        }
        .alert("Delete \(deleteCandidate?.name ?? "instance")?",
               isPresented: Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } })) {
            Button("Delete Wrapper Only") {
                if let i = deleteCandidate { state.delete(i, includingData: false) }
            }
            Button("Delete Wrapper and Data", role: .destructive) {
                if let i = deleteCandidate { state.delete(i, includingData: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("“Delete Wrapper and Data” also removes this instance's profile (its login and settings).")
        }
        .alert("Duplex", isPresented: Binding(
            get: { state.errorMessage != nil },
            set: { if !$0 { state.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(state.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func row(_ instance: Instance) -> some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: instance.wrapperURL.path))
                .resizable().frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(instance.name).font(.headline)
                Text("\(instance.targetBundleID) · \(ByteCountFormatter.string(fromByteCount: state.dataSizes[instance.slug] ?? 0, countStyle: .file))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Launch") { state.launch(instance) }
            Menu {
                Button("Edit…") { editorTarget = .edit(instance) }
                Button("Launch Original App") { state.launchOriginal(instance) }
                Button("Reveal Data Folder") { state.revealData(instance) }
                if !instance.urlSchemes.isEmpty {
                    Button("Route Links Here") { state.routeLinks(to: instance) }
                    Button("Route Links to Original App") { state.routeLinksToOriginal(instance) }
                }
                Divider()
                Button("Delete…", role: .destructive) { deleteCandidate = instance }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 32)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var licenseStatus: some View {
        if license.isLicensed {
            Text("Licensed").font(.caption).foregroundStyle(.secondary)
        } else {
            HStack(spacing: 4) {
                Text("Free \u{00B7} \(min(state.instances.count, 1)) of 1 free instance used \u{00B7}")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Enter License\u{2026}") { state.showLicenseSheet = true }
                    .buttonStyle(.link).font(.caption)
            }
        }
    }
}
