import AppKit
import SwiftUI
import DuplexKit

struct InstanceListView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var license: LicenseManager
    @Environment(\.colorScheme) private var colorScheme
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

    private let gridColumns = [GridItem(.adaptive(minimum: 210, maximum: 300), spacing: 16)]

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            footer
        }
        .background(DuplexTheme.windowGradient(colorScheme).ignoresSafeArea())
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
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color(nsColor: .controlBackgroundColor).opacity(0.7)))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06)))
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
        .buttonStyle(PillButtonStyle(compact: true))
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
                LazyVGrid(columns: gridColumns, spacing: 16) {
                    ForEach(filteredInstances) { instance in
                        InstanceCard(
                            instance: instance,
                            onEdit: { editorTarget = .edit(instance) },
                            onDelete: { deleteCandidate = instance })
                    }
                }
                .padding(16)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 92, height: 92)
                .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
            Text("Run a second copy of any Electron app")
                .font(.system(size: 21, weight: .bold))
            Text("Create a wrapper to get a second Claude, Slack, or Discord with its own login and settings, while the original stays untouched.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 400)
            Button("Create Your First Instance") { editorTarget = .new }
                .buttonStyle(PillButtonStyle())
                .padding(.top, 8)
            HStack(spacing: 5) {
                Text("or press").font(.caption).foregroundStyle(.tertiary)
                Keycap(label: "\u{2318}")
                Keycap(label: "N")
            }
            .padding(.top, 2)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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

/// One instance as a floating card: a pastel hero zone holding the
/// ghost-and-copy icon pair (the original app peeking from behind the
/// instance's own icon), then name, target, profile size, and actions.
private struct InstanceCard: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) private var colorScheme
    let instance: Instance
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                DuplexTheme.heroGradient(colorScheme)
                iconPair
            }
            .frame(height: 92)
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(instance.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text("\(targetAppName)  \u{00B7}  \(sizeText)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack {
                    Button("Launch") { state.launch(instance) }
                        .buttonStyle(PillButtonStyle(compact: true))
                    Spacer()
                    actionsMenu
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .clipShape(RoundedRectangle(cornerRadius: DuplexTheme.cardCorner, style: .continuous))
        .modifier(InstanceCardStyle(hovering: hovering))
        .onHover { hovering = $0 }
    }

    /// The signature mark: a faded miniature of the original app behind the
    /// instance's icon, the same gesture as the Duplex app icon.
    private var iconPair: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: instance.targetPath))
                .resizable().frame(width: 38, height: 38)
                .opacity(0.4)
            Image(nsImage: NSWorkspace.shared.icon(forFile: instance.wrapperURL.path))
                .resizable().frame(width: 50, height: 50)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
        }
        .frame(width: 64, height: 58, alignment: .bottomTrailing)
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
