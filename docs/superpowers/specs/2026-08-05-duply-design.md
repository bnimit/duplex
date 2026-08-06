# Duplex — Multi-Instance Wrapper Generator for macOS

**Date:** 2026-08-05
**Status:** Approved (rev 2 — core mechanism corrected after empirical validation)

## Problem

macOS enforces one running instance per app: LaunchServices refuses a second launch of the same bundle ID, and Electron apps additionally take a single-instance lock keyed on their user data directory. Apps like Claude Desktop therefore support only one logged-in account at a time.

## Goal

A small SwiftUI utility ("Duplex") that generates lightweight wrapper `.app` bundles. Each wrapper launches an existing **Electron/Chromium-based** app as an independent instance with its own data namespace, enabling e.g. two Claude Desktop instances logged into different accounts simultaneously.

## Non-Goals (YAGNI)

- Non-Electron apps (see "Why Electron-only" below; refused at creation with an explanation).
- Sandboxed / Mac App Store apps.
- Full copy + re-sign mode.
- Menu bar extra, auto-update of Duplex itself, Windows/Linux.

## Core Technique (empirically validated on this machine, macOS 26.5)

Each wrapper's launcher `exec`s the target app's inner binary with Chromium's
`--user-data-dir=<instance data dir>` switch. Electron honors it: the entire
profile (cookies, Local Storage, IndexedDB, session) lands in the given
directory, and Electron's single-instance lock is keyed on that directory, so
instances never collide.

Validation performed (2026-08-05, Claude Desktop 1.25927.0):

- `Claude --user-data-dir=/tmp/x` wrote a full profile (332 files) to `/tmp/x`.
- Original + isolated instance ran simultaneously, each with its own session
  (the isolated one showed a fresh login screen).
- **HOME redirection — the classic technique — is dead on modern macOS:**
  `NSHomeDirectory()`/`NSSearchPathForDirectoriesInDomains` resolve via
  `getpwuid`, ignoring the `$HOME` env var (verified with a compiled probe);
  Claude launched with a redirected HOME wrote zero files there.

Because HOME is untouched, no symlink tricks are needed: file dialogs,
`~/Documents`, and Claude Code/MCP integration (`~/.claude`) work natively in
every instance.

### Why Electron-only

`--user-data-dir` is a Chromium/Electron switch. Native apps would need HOME
redirection (dead, see above) or copy+re-sign (out of scope). Electron covers
the multi-account apps that matter: Claude, Slack, Discord, Signal, VS Code,
Cursor, Postman… (11 Electron apps are installed on this machine alone).
Detection: presence of `Contents/Frameworks/Electron Framework.framework` in
the target bundle.

## Architecture

Swift Package with three targets plus a bundling script:

1. **DuplexKit** (library) — all logic, unit-tested: app inspection, slug/plist
   generation, wrapper assembly, icon badging, instance scanning, URL-scheme
   routing.
2. **Duplex** (executable) — SwiftUI, single window. Thin UI over DuplexKit.
3. **duplex-launcher** (executable) — tiny binary copied into every generated
   wrapper.
4. `scripts/build-app.sh` — assembles distributable `Duplex.app` (embeds the
   launcher in its Resources) and ad-hoc signs it.

There is no separate database: the instance registry is the wrapper bundles on
disk plus their data folders. Duplex discovers instances by scanning the wrapper
output folder for bundles whose Info.plist carries Duplex's custom keys.

### Generated wrapper bundle (~200 KB)

```
Claude Work.app/
└── Contents/
    ├── Info.plist        # CFBundleIdentifier: com.duplex.<slug>
    │                     # CFBundleName: user-chosen name
    │                     # CFBundleURLTypes: copied from target (see URL routing)
    │                     # custom keys: DuplexTargetBundleID, DuplexTargetPath,
    │                     #              DuplexInstanceSlug, DuplexInstanceName
    ├── MacOS/duplex-launcher
    └── Resources/icon.icns
```

The wrapper is ad-hoc code-signed at creation (`codesign -s -`) so Gatekeeper
and TCC permission grants stay stable. Wrappers are written to `/Applications`,
falling back to `~/Applications` if not writable. Locally created bundles carry
no quarantine attribute, so Gatekeeper does not block them.

### Launcher behavior (runs on every instance launch)

1. Read config from its own bundle's Info.plist (the Duplex* keys).
2. Resolve the target app: by `DuplexTargetBundleID` via LaunchServices first
   (survives moves and updates), `DuplexTargetPath` as fallback.
3. Ensure the instance data dir exists:
   `~/Library/Application Support/Duplex/<slug>/data/`.
4. `exec` the target's inner binary (`Contents/MacOS/<CFBundleExecutable>`)
   with `--user-data-dir=<data dir>` appended — not `open`, which would route
   to an already-running instance. `exec` keeps the wrapper's process identity,
   so the Dock shows the wrapper's icon and label.

## UI

**Main window** — list of instances: badge/custom icon, instance name, target
app, data folder size. Row actions: **Launch**, **Reveal Data Folder**,
**Edit** (rename / change icon; regenerates the wrapper in place, data
untouched), **Route links here** (see URL routing), **Delete** (asks whether to
also delete the data folder).

**New Instance sheet** — target app picker (NSOpenPanel over /Applications),
name field, icon choice: **colored badge** over the target's icon (default) or
**custom image** (PNG/ICNS dropped in; Duplex converts to icns). On create,
Duplex checks for `Electron Framework.framework` and refuses non-Electron apps
with a plain-English explanation.

## URL-Scheme / OAuth Login Routing

Claude Desktop's login bounces through the browser and returns via a
`claude://` deep link; macOS routes a scheme to exactly one handler. Wrappers
therefore declare the target's `CFBundleURLTypes` too, and each instance row
has a **"Route links here"** toggle (LaunchServices default-handler API) so the
user claims the scheme for the instance they are about to log into, then hands
it back to the original app. Without this, a second instance could never
complete browser-based login.

## Error Handling & Known Quirks

| Situation | Behavior |
|---|---|
| Non-Electron target selected | Refused at creation with explanation |
| Target app uninstalled/moved | Launcher shows an alert (not a silent exit) |
| Duplicate instance name | Slug auto-suffixed (`claude-work-2`) |
| Same wrapper launched twice | Target's single-instance lock (keyed on data dir) focuses the existing window — harmless |
| Original app launched from Dock/Finder while an instance is running | LaunchServices may focus the instance instead of launching the original (observed). Documented; launching the original first avoids it |
| Delete instance | Confirm dialog; optional deletion of data folder |
| Per-instance TCC prompts | Expected once per wrapper (mic/camera/notifications are per-bundle-ID); documented |
| Preferences (`NSUserDefaults`) shared across instances | Accepted: Electron apps keep state in the profile dir, not in plists |
| Menu-bar app name | Electron apps draw their own menu-bar title, so it may still read "Claude" while the Dock shows the instance name; documented |
| Stale wrapper icon after target update | Edit → regenerate refreshes the badge |

## Testing

- **Unit tests (DuplexKit):** Electron detection, slug generation/uniqueness,
  Info.plist generation, icon badge compositing, instance scanning, launcher
  argument construction.
- **E2E smoke script:** generate a wrapper around a synthesized fake "Electron
  app" whose binary dumps its argv/env to a file; launch the wrapper; assert
  the data dir was created and `--user-data-dir` was passed.
- **Acceptance:** two Claude Desktop instances running side by side, logged
  into different accounts (mechanics already validated by hand on
  2026-08-05).
