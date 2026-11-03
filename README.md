<p align="center">
  <img src="docs/icon.png" width="128" alt="Keysy icon">
</p>

<h1 align="center">Keysy</h1>

<p align="center">A tiny macOS menu bar app that remaps key combinations — and lets you change macOS's own shortcuts (window tiling, screenshots, input sources) to keys you like.</p>

<p align="center">
  <a href="https://github.com/jojonki/Keysy/releases/latest"><img src="https://img.shields.io/github/v/release/jojonki/Keysy" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="macOS">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License"></a>
  <a href="https://github.com/sponsors/jojonki"><img src="https://img.shields.io/github/sponsors/jojonki?label=Sponsor&logo=GitHub" alt="Sponsor"></a>
</p>

<p align="center">
  <img src="docs/screenshot.png" width="640" alt="Keysy's macOS Shortcuts tab listing window tiling commands and their shortcuts">
</p>

## Features

### Key Remaps
- **Any number of remaps** (key → key), each with its own on/off switch
- **Record by typing** — click a field and press the keys
- Example: ⌘9 → ⌃⇧⇥ (previous tab), ⌘0 → ⌃⇥ (next tab)
- Starts empty; nothing is remapped until you add it

### macOS Shortcuts
Change the shortcut of macOS built-in features — only the ones you pick:

| Group          | Features |
|----------------|----------|
| Window         | Fill, Center, Left, Right, Top, Bottom, Left & Right, Right & Left, Top & Bottom, Bottom & Top, … & Quarters, Return to Previous Size |
| Screenshots    | Save/copy screen, save/copy selected area, Screenshot & recording options |
| Input Sources  | Select previous / next input source |

Keysy doesn't imitate these features; it writes your shortcut into **macOS's own settings**,
the same place System Settings ▸ Keyboard ▸ Keyboard Shortcuts uses:

- Window commands → *App Shortcuts* (All Applications), using the menu titles in your language
  (taken from AppKit's localization) plus English
- Screenshots / Input Sources → the system keyboard-shortcut settings

Each row shows macOS's official shortcut and a **Default / Custom / Off** badge;
↩︎ resets that row to the official shortcut.

**Window commands apply to apps launched after the change** — macOS reads App Shortcuts only when an
app starts, so quit and reopen apps that were already running (Keysy offers to relaunch Finder).
Because the settings live in macOS, they keep working even when Keysy isn't running.

> **Replacing Snappy:** set *Left* → ⌃⌘←, *Right* → ⌃⌘→, *Fill* → ⌃⌘↑ in the Window group,
> then quit [Snappy](https://github.com/jojonki/Snappy).

### Also
- Launch at login, automatic update check from GitHub Releases
- Links to this repository and to sponsorship from the menu

## Install

Download `Keysy.dmg` from [Releases](https://github.com/jojonki/Keysy/releases), drag Keysy to Applications,
then grant **Accessibility** permission when prompted
(System Settings → Privacy & Security → Accessibility). Key Remaps need it to read and send key events;
macOS Shortcuts don't.

## Build

```sh
./build.sh                            # builds build/Keysy.app, .zip and .dmg
VERSION=0.1.0 ./build.sh              # set the version
NOTARY_PROFILE=<profile> ./build.sh   # also notarize
```

The app icon is generated from `Resources/icon.png`.
Releases are published as `vX.Y.Z` tags with `Keysy.zip` attached; the in-app updater installs that zip.

## Support

If Keysy is useful to you, please consider [sponsoring me on GitHub](https://github.com/sponsors/jojonki) ♥
You can also reach it from the menu bar: **Support the Developer ♥**.

Bug reports and feature requests are welcome in [Issues](https://github.com/jojonki/Keysy/issues).

## License

[MIT](LICENSE) © Junki Ohmura
