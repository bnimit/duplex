# Duply — Multi-Instance Wrapper Generator for macOS

**Date:** 2026-08-05
**Status:** Approved

## Problem

macOS enforces one running instance per app: LaunchServices refuses a second launch of the same bundle ID, and Electron apps additionally take a single-instance lock keyed on their user data directory. Apps like Claude Desktop therefore support only one logged-in account at a time.

## Goal

A small SwiftUI utility ("Duply") that generates lightweight wrapper `.app` bundles. Each wrapper launches an existing **non-sandboxed** app as an independent instance with its own data namespace, enabling e.g. two Claude Desktop instances logged into different accounts simultaneously.

## Non-Goals (YAGNI)

- Sandboxed / Mac App Store apps (their containers are keyed to bundle ID; refused at creation with an explanation).
- Full copy + re-sign mode.
- Menu bar extra, auto-update of Duply itself, Windows/Linux.

## Core Technique (validated against Parall and the local Claude.app)

Claude Desktop (`com.anthropic.claudefordesktop`) is signed but **not App-Sandboxed** — it resolves its data directory from `$HOME` at launch. Launching the same binary with a redirected `HOME` yields a fresh `Library/Application Support/<App>`, a fresh single-instance lock, and fresh preferences (`CFPreferences` resolves via `NSHomeDirectory()`, which honors the `HOME` env var). No copy of the target app, no re-signing, no binary modification; the original app keeps auto-updating and every instance runs the updated version.

## Architecture

Two build products in one Xcode project:

1. **Duply.app** — SwiftUI, single window. Creates, lists, edits, launches, and deletes instances.
2. **launcher** — a tiny compiled Swift executable, embedded in Duply's resources and copied into every generated wrapper.

There is no separate database: the instance registry is the wrapper bundles on disk plus their data folders. Duply discovers instances by scanning the wrapper output folder for bundles whose Info.plist carries Duply's custom keys.

### Generated wrapper bundle (~200 KB)

```
Claude Work.app/
└── Contents/
    ├── Info.plist        # unique CFBundleIdentifier: com.duply.<slug>
    │                     # CFBundleName: user-chosen name
    │                     # custom keys: DuplyTargetBundleID, DuplyTargetPath (fallback),
    │                     #              DuplyInstanceSlug
    ├── MacOS/launcher    # the compiled generic launcher
    └── Resources/icon.icns
```

The wrapper is ad-hoc code-signed at creation (`codesign -s -`) so Gatekeeper and TCC permission grants stay stable. Wrappers are written to `/Applications`, falling back to `~/Applications` if not writable. Locally created bundles carry no quarantine attribute, so Gatekeeper does not block them.

### Launcher behavior (runs on every instance launch)

1. Resolve the target app: by `DuplyTargetBundleID` via LaunchServices first (survives moves and updates), `DuplyTargetPath` as fallback.
2. Ensure the fake home exists: `~/Library/Application Support/Duply/<slug>/home/`.
3. Symlink the real `Documents`, `Downloads`, `Desktop`, `Pictures`, `Movies`, `Music`, and `~/.claude` (when present) into the fake home — file access and Claude Code/MCP integration keep working while `Library/` stays private. Symlinks are created only if missing.
4. `exec` the target's inner binary (`Contents/MacOS/<exec>`) — not `open`, which would route to the already-running instance — with `HOME` set to the fake home. `exec` keeps the wrapper's process identity, so the Dock shows the wrapper's icon and label.

## UI

**Main window** — list of instances: badge/custom icon, instance name, target app, data folder size. Row actions: **Launch**, **Reveal Data Folder**, **Edit** (rename / change icon; regenerates the wrapper in place, data untouched), **Route links here** (see URL schemes), **Delete** (asks whether to also delete the data folder).

**New Instance sheet** — target app picker (NSOpenPanel over /Applications), name field, icon choice: **colored badge** over the target's icon (default) or **custom image** (PNG/ICNS dropped in; Duply converts to icns). On create, Duply reads the target's entitlements (`SecStaticCode` / `codesign -d --entitlements`) and refuses sandboxed apps with a plain-English explanation.

## URL-Scheme / OAuth Login Routing

Claude Desktop's login bounces through the browser and returns via a `claude://` deep link; macOS routes a scheme to exactly one handler. Wrappers therefore declare the target's `CFBundleURLTypes` too, and each instance row has a **"Route links here"** toggle (LaunchServices default-handler API) so the user claims the scheme for the instance they are about to log into, then hands it back. Without this, a second instance could never complete browser-based login.

## Error Handling & Known Quirks

| Situation | Behavior |
|---|---|
| Sandboxed target selected | Refused at creation with explanation |
| Target app uninstalled/moved | Launcher shows an alert (not a silent exit) |
| Duplicate instance name | Slug auto-suffixed (`claude-work-2`) |
| Same wrapper launched twice | Target's own single-instance lock focuses the existing window — harmless |
| Delete instance | Confirm dialog; optional deletion of data folder |
| Per-instance TCC prompts | Expected once per wrapper (mic/camera/notifications are per-bundle-ID); documented |
| File dialogs default to fake home | Real folders are one symlink away; documented |
| Menu-bar app name | Electron apps draw their own menu-bar title, so it may still read "Claude" while Dock shows the instance name; documented |
| Stale wrapper icon after target update | Edit → regenerate refreshes the badge |

## Testing

- **Unit tests:** slug generation/uniqueness, Info.plist generation, entitlement sniffing (sandboxed detection), icon badge compositing.
- **E2E smoke script:** wrap a trivial test app; assert fake home + symlinks are created and `HOME` is redirected in the child's environment.
- **Acceptance:** two Claude Desktop instances running side by side, logged into different accounts. Launcher mechanics verified against the real `/Applications/Claude.app` during implementation.
