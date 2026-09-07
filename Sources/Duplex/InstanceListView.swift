import AppKit
import SwiftUI
import DuplexKit

struct InstanceListView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var license: LicenseManager
    @EnvironmentObject var updates: UpdateManager
    @State private var editorTarget: EditorTarget?
    @State private var deleteCandidate: Instance?
    @State private var searchText = ""
    @State private var copiedCommand = false
    /// Fixed for the life of the window: how this copy of Duplex was installed.
    private let installMethod = InstallMethod.detect()

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

    /// Instances grouped into one quiet section per target app.
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
        NavigationStack {
            content
                .toolbar { toolbarItems }
                .searchable(text: $searchText, prompt: "Search instances")
        }
        .safeAreaInset(edge: .top, spacing: 0) { updateBanner }
        .safeAreaInset(edge: .bottom, spacing: 0) { statusBar }
        // Profile sizes are cached (walking large profiles per repaint is too
        // slow), so re-scan whenever the app comes back to the foreground:
        // returning from a freshly launched instance shows its real size.
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            state.refresh()
        }
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
        .alert("\(state.blockedAction?.instance.name ?? "This instance") is running",
               isPresented: Binding(get: { state.blockedAction != nil },
                                    set: { if !$0 { state.blockedAction = nil } })) {
            Button("Quit and Continue") {
                guard let action = state.blockedAction else { return }
                state.blockedAction = nil
                Task {
                    guard await state.quitAndContinue(action) else { return }
                    switch action {
                    case .edit(let i): editorTarget = .edit(i)
                    case .delete(let i): deleteCandidate = i
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Changing or deleting an instance while it runs would pull the app out from under it. Duplex can quit it first.")
        }
        .alert("Instances updated", isPresented: Binding(
            get: { state.migrationNotice != nil },
            set: { if !$0 { state.migrationNotice = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(state.migrationNotice ?? "")
        }
    }

    // MARK: - Toolbar

    private var toolbarIcon: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable().frame(width: 22, height: 22)
    }

    private var newInstanceToolbarButton: some View {
        Button {
            if state.canCreateNewInstance {
                editorTarget = .new
            } else {
                state.showLicenseSheet = true
            }
        } label: {
            Label("New Instance", systemImage: "plus")
        }
        .modifier(ProminentActionStyle())
        .keyboardShortcut("n")
        .help("Wrappers are saved to \(state.outputDir.path)")
        .disabled(state.isBusy)
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        if #available(macOS 26.0, *) {
            // The bare icon is decorative: opt it out of Liquid Glass's
            // per-item capsule background.
            ToolbarItem(placement: .navigation) { toolbarIcon }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .navigation) { toolbarIcon }
        }
        ToolbarItem(placement: .primaryAction) { newInstanceToolbarButton }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if state.instances.isEmpty {
            emptyState
        } else if filteredInstances.isEmpty {
            noMatches
        } else {
            List {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.instances) { instance in
                            row(instance)
                        }
                    } header: {
                        sectionHeader(group)
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .background(alignment: .bottomTrailing) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 300, height: 300)
                    .opacity(0.05)
                    .padding(20)
                    .allowsHitTesting(false)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private func sectionHeader(_ group: AppGroup) -> some View {
        HStack(spacing: 6) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: group.appURL.path))
                .resizable().frame(width: 16, height: 16)
            Text(group.appName)
            Text("\(group.instances.count)")
                .foregroundStyle(.tertiary)
            Spacer()
            Button {
                if state.canCreateNewInstance {
                    editorTarget = .newForApp(group.appURL)
                } else {
                    state.showLicenseSheet = true
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("New \(group.appName) instance")
        }
    }

    private func row(_ instance: Instance) -> some View {
        HStack(spacing: 12) {
            iconPair(instance)
            VStack(alignment: .leading, spacing: 2) {
                Text(instance.name)
                    .font(.system(size: 13, weight: .medium))
                Text(ByteCountFormatter.string(
                    fromByteCount: state.dataSizes[instance.slug] ?? 0, countStyle: .file))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if state.needsRebuild(instance) {
                    Text("Rebuilds on next launch (app updated)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Launch") { state.launch(instance) }
                .modifier(ProminentActionStyle())
                .controlSize(.small)
                .fixedSize()
                .disabled(state.isBusy)
            actionsMenu(instance)
        }
        .padding(.vertical, 5)
        .contextMenu { menuItems(instance) }
    }

    /// The signature mark, kept quiet: a faded miniature of the original app
    /// behind the instance's own icon.
    private func iconPair(_ instance: Instance) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: instance.targetPath))
                .resizable().frame(width: 26, height: 26)
                .opacity(0.38)
            Image(nsImage: NSWorkspace.shared.icon(forFile: instance.wrapperURL.path))
                .resizable().frame(width: 36, height: 36)
        }
        .frame(width: 46, height: 40, alignment: .bottomTrailing)
    }

    private func actionsMenu(_ instance: Instance) -> some View {
        Menu {
            menuItems(instance)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private func menuItems(_ instance: Instance) -> some View {
        Button("Edit\u{2026}") {
            if state.guardNotRunning(.edit(instance)) { editorTarget = .edit(instance) }
        }
        Button("Reveal Data Folder") { state.revealData(instance) }
        if !instance.urlSchemes.isEmpty {
            Button("Route Links Here") { state.routeLinks(to: instance) }
            Button("Route Links to Original App") { state.routeLinksToOriginal(instance) }
        }
        Divider()
        Button("Delete\u{2026}", role: .destructive) {
            if state.guardNotRunning(.delete(instance)) { deleteCandidate = instance }
        }
    }

    // MARK: - Empty / no-match states

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 84, height: 84)
            Text("Run a second copy of any Electron app")
                .font(.title3).bold()
            Text("Create a wrapper to get a second Claude, Slack, or Discord with its own login and settings, while the original stays untouched.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 400)
            Button("Create Your First Instance") { editorTarget = .new }
                .modifier(ProminentActionStyle())
                .padding(.top, 6)
            HStack(spacing: 5) {
                Text("or press").font(.caption).foregroundStyle(.tertiary)
                Keycap(label: "\u{2318}")
                Keycap(label: "N")
            }
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

    // MARK: - Update banner

    /// Shown only when a newer release exists and the user has not dismissed
    /// that version. Duplex never installs anything itself, so the banner's job
    /// is to give the one step that applies to how this copy was installed.
    @ViewBuilder
    private var updateBanner: some View {
        if let update = updates.available {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(DuplexTheme.indigo)
                    Text("Duplex \(update.version) is available")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    switch installMethod {
                    case .homebrew:
                        Text("Update with")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(DuplexConfig.upgradeCommand)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                        Button(copiedCommand ? "Copied" : "Copy") { copyUpgradeCommand() }
                            .buttonStyle(.link)
                            .font(.system(size: 11))
                            .disabled(copiedCommand)
                    case .direct:
                        Button("Download \(update.version)\u{2026}") {
                            NSWorkspace.shared.open(update.url)
                        }
                        .controlSize(.small)
                    }
                    Button { updates.dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Hide this until the next version")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.bar)
                Divider()
            }
        }
    }

    private func copyUpgradeCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(DuplexConfig.upgradeCommand, forType: .string)
        copiedCommand = true
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            copiedCommand = false
        }
    }

    // MARK: - Status bar

    private var statusBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 6) {
                Text("Duplex \(DuplexConfig.appVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\u{00B7}")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
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
                Spacer()
                if state.isBusy {
                    ProgressView().controlSize(.small)
                    Text("Working\u{2026}").font(.caption).foregroundStyle(.secondary)
                }
                Text(state.outputDir.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help("Wrappers are saved here")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)
        }
    }
}
