# Duplex

Duplex is a small macOS utility for running multiple, independent instances of
an Electron-based app side by side, such as two Claude Desktop windows
logged into two different accounts at the same time. macOS normally refuses to
launch a second copy of the same app, and Electron apps additionally lock
their profile directory, so this doesn't work out of the box. Duplex works
around both by creating a lightweight clone of the app for each instance: a
copy-on-write copy of the app bundle that shares its disk blocks with the
original, carries its own identity so macOS treats it as a separate app, and
starts the app with a private data directory. Every instance gets its own
cookies, local storage, and login session, and the original app is never
modified.

## Install

```
brew tap bnimit/tap
brew trust bnimit/tap
brew install --cask duplex
```

(`brew trust` is a one-time step Homebrew requires for third-party taps.)
Or download the notarized zip from the
[latest release](https://github.com/bnimit/duplex/releases/latest).

## How it works

Each instance Duplex creates is a clone of the target app, not a shortcut to it.

1. The app bundle is cloned with APFS copy-on-write, so the clone shares disk
   blocks with the original and takes about two seconds to make. Finder reports
   it at the app's full size, but it costs almost no space.
2. The clone's Info.plist gets a new bundle identifier (`com.duplex.<slug>`),
   your instance name, and your chosen icon. Everything else stays as the app
   shipped it.
3. The app's own binary and helper apps inside the clone are re-signed with an
   ad-hoc signature so macOS accepts the changed identity. The large frameworks
   keep the vendor's signature untouched.
4. A small launcher inside the clone starts the app's binary with
   `--user-data-dir=~/Library/Application Support/Duplex/<slug>/data`, which
   Electron/Chromium honors by keeping the whole profile, including the
   single-instance lock, inside that folder.

Because the running process lives inside the clone, macOS sees a separate
application: the original launches from the Dock while instances run, and login
callbacks such as `claude://` are delivered to the instance you routed them to.

Instances follow the original app's updates. On every launch the launcher
compares the installed app's version with the one the clone was made from and
rebuilds the clone before starting it when they differ, or when the clone's copy
of the app binary is missing (for example after an interrupted rebuild). The
app's own updater inside an instance cannot install anything (it refuses to
replace an ad-hoc signed bundle), which is what keeps the clone consistent.

Instances cannot use the original app's keychain entry, because macOS ties it
to the vendor's signing identity. They therefore run with Chromium's
`--use-mock-keychain` switch: the saved session is encrypted with a fixed key
and protected by your macOS user account permissions, the same model Chromium
uses on Linux without a keyring. The original app is unaffected.

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
   "Claude Work"), and choose an icon. By default the instance gets an exact,
   full-resolution copy of the target app's own icon; a colored badge over
   that icon or a custom image are also available. Note that the Dock only
   shows app names on hover, so if you run the original and a clone side by
   side and want to tell them apart at a glance, pick the badge or a custom
   image. Duplex generates and signs the clone.
2. **Launch it**: click Launch on the instance's row, or open it from
   `/Applications` like any app. The clone starts with its own private data
   directory, so it opens to a fresh, logged-out state the first time. The
   original app keeps launching normally from the Dock while instances run.
3. **Log in**: before logging in, use the instance's "Route Links Here" action
   so that OAuth/deep-link callbacks (e.g. `claude://...`) come back to this
   instance instead of the original app or another instance. Complete the
   login in the instance's window, then hand the link routing back to the
   original app (or whichever instance you'll use next) so future logins go
   to the right place.

## Known Quirks

| Situation | Behavior |
|---|---|
| Non-Electron target selected | Refused at creation with explanation |
| Target app uninstalled/moved | Launcher shows an alert (not a silent exit) |
| Duplicate instance name | Refused at creation ("pick a different instance name"); the slug auto-suffix (`claude-work-2`) only applies when two *different* names collide after slugging |
| Same instance launched twice | Target's single-instance lock (keyed on data dir) focuses the existing window, which is harmless |
| Instance size in Finder | Finder and `du` report the app's full size, but the clone is copy-on-write and shares disk blocks with the original until the original updates; the next instance launch rebuilds the clone and the sharing resumes |
| Permissions asked again after the original app updates | Rebuilding a clone re-signs it, and macOS ties permissions such as Desktop or microphone access to the signature, so an instance may ask again |
| Editing or deleting a running instance | Duplex asks to quit the instance first, because the change replaces the bundle the app is running from |
| Upgrading from Duplex 1.1 | Existing instances are rebuilt as clones on first launch (one-time notice). Profiles are kept, but because session storage changed you sign in again once per instance |
| Update prompts inside an instance | The app's own updater cannot install into a clone. Update the original app; the instance follows on its next launch |
| Mac App Store builds of apps | Not supported: their receipt validation rejects a changed bundle identifier |
| Delete instance | Confirm dialog; optional deletion of data folder |
| Per-instance TCC prompts | Expected once per instance (mic/camera/notifications are per-bundle-ID) |
| Preferences (`NSUserDefaults`) shared across instances | Accepted: Electron apps keep state in the profile dir, not in plists |
| Menu-bar app name | Electron apps draw their own menu-bar title, so it may still read the original app's name while the Dock shows the instance name |
| Stale instance icon after target update | Edit → regenerate refreshes the icon |
| Passkeys, hardware security keys, Microsoft work sign-in inside an instance | Not expected to work. Ad-hoc signing cannot carry the vendor's keychain access groups, so credential storage for those flows fails inside an instance. Ordinary email and Google sign-in are unaffected |

## License

Duplex is source-available: read the code, learn from it, and build it for
your own personal use. Redistribution of the source or of compiled builds is
not permitted; see [LICENSE](LICENSE) for the exact terms. Notarized,
supported builds with a license key are sold by
[Aetrix Foundry](https://aetrixfoundry.com).
