# Duplex

Duplex is a small macOS utility for running multiple, independent instances of
an Electron-based app side by side, such as two Claude Desktop windows
logged into two different accounts at the same time. macOS normally refuses to
launch a second copy of the same app, and Electron apps additionally lock
their profile directory, so this doesn't work out of the box. Duplex works
around both restrictions by generating tiny wrapper `.app` bundles: each one
launches the target app's own binary with a private data directory, so every
instance gets its own cookies, local storage, and login session while sharing
the same underlying installation.

## How it works

Each wrapper Duplex creates is a lightweight bundle that stores a reference to
the target app (by bundle ID, with a path as fallback) plus an instance slug.
When launched, the wrapper's launcher binary resolves the target app, ensures
`~/Library/Application Support/Duplex/<slug>/data` exists, and then `exec`s the
target's real executable with `--user-data-dir=<that directory>` appended.
Electron/Chromium honors this flag by keeping the app's entire profile,
including its single-instance lock, scoped to that directory, so instances
never collide with each other or with the original app. Because the wrapper
uses `exec` rather than `open`, the Dock and window server see the wrapper's
own icon and name rather than being redirected to an already-running instance.

## Requirements

- macOS 13.0 or later
- Target apps must be Electron/Chromium-based (Duplex checks for
  `Contents/Frameworks/Electron Framework.framework` and refuses anything
  else, since `--user-data-dir` is a Chromium/Electron switch with no
  equivalent for native apps)

## Build

```
./scripts/build-app.sh
```

This builds a release binary and assembles `dist/Duplex.app`, embedding the
`duplex-launcher` binary in its Resources and ad-hoc code-signing the result.
Run `open dist/Duplex.app` to launch it.

## Usage

1. **Create an instance**: click "New Instance…", pick the target app (e.g.
   Claude Desktop) from `/Applications`, give the instance a name (e.g.
   "Claude Work"), and choose an icon. By default the wrapper gets an exact,
   full-resolution copy of the target app's own icon; a colored badge over
   that icon or a custom image are also available. Duplex generates and signs
   the wrapper bundle.
2. **Launch it**: click Launch on the instance's row. The wrapper starts the
   target app with its own private data directory, so it opens to a fresh,
   logged-out state the first time. If the original app is not running, start
   it any time via the instance's … menu → Launch Original App, which works
   even while clones are running.
3. **Log in**: before logging in, use the instance's "Route Links Here"
   toggle so that OAuth/deep-link callbacks (e.g. `claude://...`) come back to
   this instance instead of the original app or another instance. Complete the
   login in the instance's window, then hand the link routing back to the
   original app (or whichever instance you'll use next) so future logins go
   to the right place.

## Known Quirks

| Situation | Behavior |
|---|---|
| Non-Electron target selected | Refused at creation with explanation |
| Target app uninstalled/moved | Launcher shows an alert (not a silent exit) |
| Duplicate instance name | Refused at creation ("pick a different instance name"); the slug auto-suffix (`claude-work-2`) only applies when two *different* names collide after slugging |
| Same wrapper launched twice | Target's single-instance lock (keyed on data dir) focuses the existing window, which is harmless |
| Original app launched from Dock/Finder while an instance is running | LaunchServices may focus the instance instead. Use the instance's … menu → "Launch Original App" in Duplex (bypasses LaunchServices, so order never matters), or simply launch the original before the instance |
| Delete instance | Confirm dialog; optional deletion of data folder |
| Per-instance TCC prompts | Expected once per wrapper (mic/camera/notifications are per-bundle-ID) |
| Preferences (`NSUserDefaults`) shared across instances | Accepted: Electron apps keep state in the profile dir, not in plists |
| Menu-bar app name | Electron apps draw their own menu-bar title, so it may still read the original app's name while the Dock shows the instance name |
| Stale wrapper icon after target update | Edit → regenerate refreshes the icon |
