import AppKit
import SwiftUI
import DuplexKit

struct InstanceListView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var license: LicenseManager
    @State private var editorTarget: EditorTarget?
    @State private var deleteCandidate: Instance?
    @State private var searchText = ""

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

    private var filteredInstances: [Instance] {
        state.instances.filter {
            InstanceFilter.matches(name: $0.name, targetPath: $0.targetPath, query: searchText)
        }
    }

    private let gridColumns = [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 14)]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
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

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 22, height: 22)
            Text("Duplex")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            searchField
            newInstanceButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.bar)
    }

    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .disabled(state.instances.isEmpty)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
        .frame(width: 190)
    }

    private var newInstanceButton: some View {
        Button {
            if state.canCreateNewInstance {
                editorTarget = .new
            } else {
                state.showLicenseSheet = true
            }
        } label: {
            Label("New Instance", systemImage: "plus")
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut("n")
        .help("Wrappers are saved to \(state.outputDir.path)")
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if state.instances.isEmpty {
            emptyState
        } else if filteredInstances.isEmpty {
            noMatches
        } else {
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: 14) {
                    ForEach(filteredInstances) { instance in
                        InstanceCard(
                            instance: instance,
                            onEdit: { editorTarget = .edit(instance) },
                            onDelete: { deleteCandidate = instance })
                    }
                }
                .padding(14)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 88, height: 88)
            Text("Run a second copy of any Electron app")
                .font(.title2).bold()
            Text("Create a wrapper to get a second Claude, Slack, or Discord with its own login and settings, while the original stays untouched.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 400)
            Button {
                editorTarget = .new
            } label: {
                Label("New Instance", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noMatches: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32)).foregroundStyle(.secondary)
            Text("No instances match \u{201C}\(searchText)\u{201D}")
                .font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            licenseStatus
            Spacer()
            Text(state.outputDir.path)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help("Wrappers are saved here")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.bar)
    }

    @ViewBuilder
    private var licenseStatus: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(license.isLicensed ? DuplexTheme.indigo : DuplexTheme.coral)
                .frame(width: 7, height: 7)
            if license.isLicensed {
                Text("Licensed").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Free \u{00B7} \(min(state.instances.count, 1)) of 1 free instances used")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Enter License\u{2026}") { state.showLicenseSheet = true }
                    .buttonStyle(.link).font(.caption)
            }
        }
    }
}

// MARK: - Instance card

/// One instance as a card: the ghost-and-copy icon pair (the original app's
/// icon peeking from behind the instance's own), name, target, profile size,
/// and the actions.
private struct InstanceCard: View {
    @EnvironmentObject var state: AppState
    let instance: Instance
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                iconPair
                Spacer()
                actionsMenu
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(instance.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(targetAppName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(sizeText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            Button {
                state.launch(instance)
            } label: {
                Text("Launch").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(14)
        .modifier(InstanceCardStyle(hovering: hovering))
        .onHover { hovering = $0 }
    }

    /// The signature mark: a faded miniature of the original app behind the
    /// instance's icon, the same gesture as the Duplex app icon.
    private var iconPair: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: instance.targetPath))
                .resizable().frame(width: 36, height: 36)
                .opacity(0.35)
            Image(nsImage: NSWorkspace.shared.icon(forFile: instance.wrapperURL.path))
                .resizable().frame(width: 44, height: 44)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        }
        .frame(width: 58, height: 52, alignment: .bottomTrailing)
    }

    private var actionsMenu: some View {
        Menu {
            Button("Edit\u{2026}") { onEdit() }
            Button("Launch Original App") { state.launchOriginal(instance) }
            Button("Reveal Data Folder") { state.revealData(instance) }
            if !instance.urlSchemes.isEmpty {
                Button("Route Links Here") { state.routeLinks(to: instance) }
                Button("Route Links to Original App") { state.routeLinksToOriginal(instance) }
            }
            Divider()
            Button("Delete\u{2026}", role: .destructive) { onDelete() }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 24)
    }

    private var targetAppName: String {
        URL(fileURLWithPath: instance.targetPath).deletingPathExtension().lastPathComponent
    }

    private var sizeText: String {
        ByteCountFormatter.string(
            fromByteCount: state.dataSizes[instance.slug] ?? 0, countStyle: .file)
    }
}
