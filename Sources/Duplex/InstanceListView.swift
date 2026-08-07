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
        case newForApp(URL)
        case edit(Instance)
        var id: String {
            switch self {
            case .new: return "new"
            case .newForApp(let url): return "new-\(url.path)"
            case .edit(let i): return i.slug
            }
        }
    }

    private var filteredInstances: [Instance] {
        state.instances.filter {
            InstanceFilter.matches(name: $0.name, targetPath: $0.targetPath, query: searchText)
        }
    }

    /// Trello-style columns: one per target app.
    private struct AppGroup: Identifiable {
        let id: String
        let appName: String
        let appURL: URL
        let instances: [Instance]
    }

    private var groups: [AppGroup] {
        Dictionary(grouping: filteredInstances, by: \.targetBundleID)
            .map { bundleID, members in
                let path = members[0].targetPath
                return AppGroup(
                    id: bundleID,
                    appName: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
                    appURL: URL(fileURLWithPath: path),
                    instances: members.sorted { $0.name < $1.name })
            }
            .sorted { $0.appName < $1.appName }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .background(DuplexTheme.windowGradient(colorScheme).ignoresSafeArea())
        .sheet(item: $editorTarget) { target in
            switch target {
            case .new: InstanceEditorSheet(existing: nil)
            case .newForApp(let url): InstanceEditorSheet(existing: nil, prefillApp: url)
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

    // MARK: - Header (bold title row on the backdrop)

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 28, height: 28)
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            Text("Duplex")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(headerText)
            licenseChip
            Spacer()
            searchField
            newInstanceButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var headerText: Color {
        colorScheme == .dark ? Color.white : Color.black.opacity(0.82)
    }

    private var licenseChip: some View {
        Button { state.showLicenseSheet = true } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(license.isLicensed ? DuplexTheme.indigo : DuplexTheme.coral)
                    .frame(width: 6, height: 6)
                Text(license.isLicensed
                     ? "Licensed"
                     : "Free \u{00B7} \(min(state.instances.count, 1))/1")
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(.ultraThinMaterial))
        }
        .buttonStyle(.plain)
        .help(license.isLicensed
              ? "Manage your license"
              : "One instance is free; a license unlocks unlimited. Click to enter a key.")
    }

    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .frame(width: 130)
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
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(.ultraThinMaterial))
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
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(groups) { group in
                        column(for: group)
                    }
                }
                .padding(16)
            }
        }
    }

    private func column(for group: AppGroup) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 7) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: group.appURL.path))
                    .resizable().frame(width: 18, height: 18)
                Text(group.appName)
                    .font(.system(size: 13, weight: .semibold))
                Text("\(group.instances.count)")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
                Spacer()
                Button {
                    if state.canCreateNewInstance {
                        editorTarget = .newForApp(group.appURL)
                    } else {
                        state.showLicenseSheet = true
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("New \(group.appName) instance")
            }
            .padding(.horizontal, 4)

            ForEach(group.instances) { instance in
                InstanceCard(
                    instance: instance,
                    tagName: group.appName,
                    onEdit: { editorTarget = .edit(instance) },
                    onDelete: { deleteCandidate = instance })
            }
        }
        .padding(10)
        .frame(width: 252)
        .background(
            RoundedRectangle(cornerRadius: DuplexTheme.cardCorner + 4, style: .continuous)
                .fill(.ultraThinMaterial))
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 92, height: 92)
                .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
            Text("Run a second copy of any Electron app")
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(headerText)
            Text("Create a wrapper to get a second Claude, Slack, or Discord with its own login and settings, while the original stays untouched.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 400)
            Button("Create Your First Instance") { editorTarget = .new }
                .buttonStyle(PillButtonStyle())
                .padding(.top, 8)
            HStack(spacing: 5) {
                Text("or press").font(.caption).foregroundStyle(.secondary)
                Keycap(label: "\u{2318}")
                Keycap(label: "N")
            }
            .padding(.top, 2)
        }
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial))
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
}

// MARK: - Instance card

/// One instance as a Trello-style card: tag pill, icon thumb zone, title,
/// meta chips, then Launch and the actions menu.
private struct InstanceCard: View {
    @EnvironmentObject var state: AppState
    let instance: Instance
    let tagName: String
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                TagPill(text: tagName, tint: DuplexTheme.tagTint(for: instance.targetBundleID))
                Spacer()
                actionsMenu
            }
            thumbZone
            Text(instance.name)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            HStack(spacing: 10) {
                MetaChip(systemImage: "internaldrive", text: sizeText)
                if !instance.urlSchemes.isEmpty {
                    MetaChip(systemImage: "link", text: instance.urlSchemes[0] + "://")
                }
                Spacer()
                Button("Launch") { state.launch(instance) }
                    .buttonStyle(PillButtonStyle(compact: true))
            }
        }
        .padding(12)
        .modifier(InstanceCardStyle(hovering: hovering))
        .onHover { hovering = $0 }
    }

    /// The media thumb: a quiet zone holding the ghost-and-copy icon pair.
    private var thumbZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.045))
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: instance.targetPath))
                    .resizable().frame(width: 34, height: 34)
                    .opacity(0.4)
                Image(nsImage: NSWorkspace.shared.icon(forFile: instance.wrapperURL.path))
                    .resizable().frame(width: 46, height: 46)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
            }
            .frame(width: 60, height: 54, alignment: .bottomTrailing)
        }
        .frame(height: 74)
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
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 22)
    }

    private var sizeText: String {
        ByteCountFormatter.string(
            fromByteCount: state.dataSizes[instance.slug] ?? 0, countStyle: .file)
    }
}
