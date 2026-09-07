# Duplex 1.2: instances with their own identity

Date: 2026-09-07. Status: approved design, pending implementation plan.

## Problem

Duplex 1.1.x wrappers are thin shells: `duplex-launcher` execs the real
`/Applications/Claude.app/Contents/MacOS/Claude` with `--user-data-dir`. The
profile isolation works, but macOS identifies a running process by the bundle
that physically contains its executable, so every instance reports itself as
`com.anthropic.claudefordesktop`. Two shipped bugs follow:

1. Launching the original Claude from the Dock or Finder while an instance is
   running only focuses the instance (LaunchServices thinks Claude is already
   running).
2. A Google/OAuth sign-in started inside an instance comes back through the
   `claude://` URL scheme, and LaunchServices delivers it to whichever process
   it believes is `com.anthropic.claudefordesktop`, usually the original,
   which is already signed in.

Non-goal: quitting other instances is not an acceptable workaround. The
product exists so several instances run at once.

## Verified facts this design rests on (probe experiments, 2026-09-07)

- A complete APFS copy-on-write clone of Claude.app (`clonefile(2)`, 0.45s,
  shares disk blocks) with a patched `Info.plist`, ad-hoc re-signed helpers,
  main binary and launcher, and untouched Anthropic-signed frameworks, runs
  fully: main process, all four helper types, renderers, no crashes.
  LaunchServices lists it as `com.duplex.<slug>` beside the original.
- `--use-mock-keychain` is honored by Claude's Electron (42 / Chromium 148).
  It removes the "Claude Safe Storage" keychain denial (errSecAuthFailed) that
  otherwise crashes the network service, and removes the GUI prompt.
- Claude's built-in updater ran normally inside the clone ("already the latest
  version"). An update it downloads cannot replace an ad-hoc signed bundle
  (Squirrel validates the running bundle's designated requirement), which is
  the behaviour we want: instances follow the original instead.
- Dead end, do not retry: a partial bundle (symlinked frameworks, copied
  binary and helpers) makes the helpers SIGTRAP inside `ElectronMain`
  regardless of keychain settings.
- Claude's plist has `CFBundleIconName = Claude` (Assets.car). It must be
  removed from the clone or Finder ignores our `icon.icns`.
- Chromium requires parent and helper processes to share a signing identity;
  ad-hoc for all of them satisfies it.
- A clone inherits the original's extended attributes. `com.apple.provenance`
  cannot be removed but does not block an ad-hoc clone launched through
  LaunchServices (verified with `open`). `com.apple.quarantine`, present on
  dmg-installed apps that have not yet self-updated, would make Gatekeeper
  refuse the ad-hoc clone, and it is removable.

## Design

### 1. An instance is a cloned app with a patched identity

`WrapperGenerator.generate` (name kept; it still produces the instance bundle)
builds the instance in a staging bundle next to the destination, then swaps it
in, exactly as today. The build step changes:

1. Clone the target app into the staging path with `clonefile(2)`. If cloning
   fails (different volume, non-APFS), fall back to `FileManager.copyItem`.
2. Patch `Contents/Info.plist` in place, changing only:
   - `CFBundleIdentifier` = `com.duplex.<slug>`
   - `CFBundleDisplayName` = instance name
   - `CFBundleExecutable` = `duplex-launcher`
   - `CFBundleIconFile` = `icon.icns`; delete `CFBundleIconName`
   - delete `CFBundleDocumentTypes` (avoids six "Open With" entries per
     instance; URL types are kept because OAuth needs them)
   - add the Duplex keys: `DuplexTargetBundleID`, `DuplexTargetPath`,
     `DuplexInstanceSlug`, `DuplexInstanceName`, plus two new keys
     `DuplexFormatVersion = 2` and `DuplexSourceVersion` = the target's
     `CFBundleShortVersionString` and `CFBundleVersion` joined as
     `"<short> (<build>)"` at clone time, so either changing triggers a
     re-sync.
   Everything else (notably `CFBundleName`, from which Electron derives the
   helper app names, and `ElectronAsarIntegrity`) is left as is.
3. Delete `Contents/embedded.provisionprofile` (meaningless under ad-hoc
   signing; its entitlements cannot be honoured anyway). Remove
   `com.apple.quarantine` recursively from the clone; Duplex created these
   files locally, so the flag would only ever be an inherited artefact.
   Also delete `UTExportedTypeDeclarations` and `UTImportedTypeDeclarations`
   from the plist if present (Claude has none; other apps may).
4. Copy the launcher to `Contents/MacOS/duplex-launcher` (0755). The original
   executable stays as its sibling.
5. Write `Contents/Resources/icon.icns` using the existing `IconChoice` logic
   (`.original` copies the target's own icns; `.keepExisting` copies the old
   wrapper's icon during regeneration).
6. Sign, ad-hoc, innermost first: every `Contents/Frameworks/*.app` helper,
   every executable file in `Contents/MacOS` (the original app's binary and
   `duplex-launcher`; some Electron apps ship more than one), then the bundle
   itself without `--deep`. Frameworks keep their vendor signature.
7. Swap staging into place (existing stage-and-swap, `destinationOccupied`
   protection unchanged) and `LSRegisterURL`.

Generation takes about two seconds on the clone path and can take tens of
seconds on the copy fallback, so `AppState.create` runs the generator off the
main actor and exposes an `isBusy` state; the list view disables the create and
edit controls and shows a small progress indicator while it is set.

Pure logic lives in a new `InstancePlist` (patch a plist dictionary given a
spec and source version; testable without a filesystem). `WrapperPlist` is
removed; its two tests move to `InstancePlist`.

### 2. Launch

`duplex-launcher` reads its own bundle's plist (existing `LauncherLogic.config`,
extended with `sourceVersion`), resolves the original app (existing
`resolveTarget`), performs the drift check (section 3), creates the data dir,
then `execv`s the sibling executable named by the target's `CFBundleExecutable`
with:

    --user-data-dir=<home>/Library/Application Support/Duplex/<slug>/data
    --use-mock-keychain

Data dir location is unchanged from 1.1, so profiles are kept.

### 3. Drift: following the original's updates

`LauncherLogic.needsResync(recorded: String?, installed: String?) -> Bool`
returns true when both are present and differ. When true, the launcher
regenerates itself: it calls `WrapperGenerator(launcherBinary: own executable)
.generate(spec, icon: .keepExisting, outputDir: own parent directory)`, which
stages a fresh clone of the updated original and swaps it in at the same path.
The running launcher's inode survives the swap; after it returns, the launcher
execs the new sibling executable. Cost is about two seconds, no UI.

Two launchers for the same slug could race (a fast double click before
LaunchServices sees the first process). The re-sync step takes an exclusive
`flock` on `<home>/Library/Application Support/Duplex/<slug>/resync.lock`; the
loser re-reads the bundle after the lock is released and finds nothing to do.

If regeneration fails (not writable, target vanished mid-way), the launcher
logs to stderr and execs the existing, stale but self-consistent clone. Only
if that exec also fails does it show the existing failure alert.

Between the original updating and the instance's next launch, Claude's
updater inside the instance may download an update it cannot install. That is
wasted bandwidth once per launch of an outdated instance, and nothing more.

The launcher copied into a regenerated clone is the running launcher itself,
so instances do not need Duplex.app installed to follow updates. Duplex.app
refreshes the launcher in all instances only when `DuplexFormatVersion`
changes, not on every Duplex release, to avoid needless re-signing (each
re-sign can make macOS re-ask an instance for permissions).

### 4. Migration of 1.1 instances

`InstanceStore.scan` exposes `formatVersion` (missing key means 1) and
`sourceVersion`. On `AppState.refresh`, if any instance has `formatVersion < 2`,
`AppState` regenerates each one (`isRegeneration: true`, so the licence gate is
not involved; icon `.keepExisting`), then shows one alert:

> Duplex updated N instance(s) to the new format so each has its own identity.
> Because session storage changed, sign in again in each instance.

An instance whose original app can no longer be inspected is skipped and
reported through the existing `errorMessage` path.

### 5. Product changes

- Remove `AppState.launchOriginal` and its "Launch Original App" menu item.
  Launching the original from the Dock now works.
- Distinct identities make "is this instance running" answerable
  (`NSRunningApplication.runningApplications(withBundleIdentifier:)`).
  Regenerating, renaming, or deleting a running clone would pull the bundle
  out from under its live process, so `AppState` refuses those actions while
  the instance runs and offers "Quit and continue", which terminates the
  instance and then proceeds. Migration of 1.1 wrappers is exempt: their
  process is the real Claude binary in the original bundle, so replacing the
  wrapper is harmless.
- "Route Links Here" stays and now delivers callbacks to the right running
  instance.
- Version 1.2.0, `CFBundleVersion` 6.

### 6. Documentation (no em dashes anywhere)

README: rewrite "How it works" (clone, patched identity, ad-hoc signing,
frameworks untouched, mock keychain and why); remove the Dock/Finder quirk row
and the "Launch Original App" step; add quirks: instances show full app size in
Finder but share disk with the original (APFS clones); macOS may re-ask an
instance for permissions such as Desktop access after Claude updates because
the instance is re-signed; after upgrading to 1.2 you sign in again once per
instance (the profile folder is kept, only the session encryption changed); Mac App Store builds of apps are not supported (receipt validation).

Site /duplex: fix the "No patching, no re-signing" card to describe clones
honestly. Terms: "does not include or redistribute those third party apps, and
never modifies your original installation".

### 7. Release

`scripts/build-app.sh` and `scripts/release.sh` unchanged in shape: bump
version, Developer ID sign (launcher explicitly, as today), notarize, staple,
zip, `gh release create v1.2.0`, update sha256 in `packaging/duplex.rb` and
`homebrew-tap/Casks/duplex.rb`.

## Error handling

- Clone failure on both paths: generator throws, staging removed, old wrapper
  kept (existing behaviour).
- codesign failure: same.
- Target not Electron or plist unreadable: existing `AppInspector` errors.
- Launcher drift regeneration failure: run stale clone, as above.
- Destination not writable for regeneration from the launcher: same fallback.
- Copy fallback with insufficient disk space: generator throws with the
  system error, staging removed.
- Instance running when the user edits or deletes it: refused with the
  "Quit and continue" offer, never a silent swap.

## Testing

Unit (DuplexKit, no GUI):
- `InstancePlist`: identity keys patched, `CFBundleName` and
  `ElectronAsarIntegrity` untouched, `CFBundleIconName` and
  `CFBundleDocumentTypes` removed, URL types kept, Duplex keys present,
  `DuplexFormatVersion` 2, `DuplexSourceVersion` recorded.
- `LauncherLogic.needsResync` truth table; `execArguments` includes
  `--use-mock-keychain`; config parsing with and without `sourceVersion`.
- `WrapperGenerator` against a fixture "Electron" app (`FixtureFactory` gains a
  fake helper app and `embedded.provisionprofile`): clone is a real independent
  copy, provisionprofile deleted, helpers and main binary ad-hoc signed, bundle
  verifies with `codesign --verify --strict`, existing stage-and-swap and
  bystander-protection tests still pass, regeneration with `.keepExisting`
  preserves the icon.
- `InstanceStore.scan` reports `formatVersion` 1 for a legacy plist and 2 for
  a new one.
- Quarantine flag set on the fixture app is absent from the generated clone.
- Fixture with a second executable in `Contents/MacOS` gets both signed.

Manual (user, GUI):
1. Fresh install of 1.2 over 1.1.3 with existing instances: migration alert
   appears once; instances launch and show the sign-in screen.
2. Original Claude launches from the Dock while an instance runs.
3. In an instance: Route Links Here, Sign in with Google, callback lands in
   that instance; original remains on its own account.
4. Instance created from a Claude version, then Claude updates: next instance
   launch takes about two seconds longer and runs the new version.

## Out of scope (recorded for later)

- A stable signing identity (self-signed certificate or custom designated
  requirement) so TCC grants and keychain ACLs survive re-signing. Verified
  cheap to sign with `-r 'designated => identifier "..."'`; TCC behaviour
  untested.
- Automatic scheme routing when an instance comes to the foreground.
