<p align="center">
  <img src="docs/icon.png" width="128" alt="Keysy icon">
</p>

<h1 align="center">Keysy</h1>

<p align="center">A tiny macOS menu bar app that remaps key combinations — and drives macOS's built-in window tiling from any shortcut you like.</p>

<p align="center">
  <a href="https://github.com/jojonki/Keysy/releases/latest"><img src="https://img.shields.io/github/v/release/jojonki/Keysy" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="macOS">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License"></a>
  <a href="https://github.com/sponsors/jojonki"><img src="https://img.shields.io/github/sponsors/jojonki?label=Sponsor&logo=GitHub" alt="Sponsor"></a>
</p>

<p align="center">
  <img src="docs/screenshot.png" width="640" alt="Keysy settings window with several key remaps">
</p>

## Features

- **Any number of remaps** — add as many as you want, enable/disable each one
- **Record by typing** — click a field and press the keys; no key lists to scroll through
- **Window tiling without a window manager** — map any shortcut to macOS's own
  *Window ▸ Move & Resize* commands (Left, Right, Fill, Center, Quarters, …)
- Global on/off switch from the menu bar, launch at login
- Automatic update check from GitHub Releases
- Quick links to this repository and to sponsorship from the menu

## Examples

| Trigger | Output                     | What for                               |
|---------|----------------------------|----------------------------------------|
| ⌘9      | ⌃⇧⇥                        | Previous tab                           |
| ⌘0      | ⌃⇥                         | Next tab                               |
| ⌃⌘←     | 🪟 Left Half (window action) | Tile window to the left half         |
| ⌃⌘→     | 🪟 Right Half (window action)| Tile window to the right half        |
| ⌃⌘↑     | 🪟 Fill Screen (window action)| Fill the screen                     |

Keysy starts with no remaps — these are just ideas. Window actions are not keys; they run a
macOS window command (picked from the `⋯` menu next to the output field).

### Replacing Snappy

macOS 15+ ships window tiling (🌐⌃← / → / F …). Keysy maps your own shortcuts to those
commands, so the window examples above (or **Add Window Tiling Presets**) reproduce [Snappy](https://github.com/jojonki/Snappy)'s
⌃⌘← / ⌃⌘→ / ⌃⌘↑ behaviour. Quit Snappy (or clear its shortcuts) to avoid both apps reacting.

Window actions press the frontmost app's *Window ▸ Move & Resize* menu item through
Accessibility (matched by its shortcut, so any UI language works). Apps without that menu
receive the 🌐⌃ shortcut keystroke instead.

## Usage

1. Open **Settings…** from the keyboard icon in the menu bar.
2. Click **Add Remap**, click the *Trigger* field and type the keys you want to press.
3. Click the *Output* field and type the keys Keysy should send — or pick a
   **macOS Window Tiling** action from the `⋯` menu.

Press **Esc** while recording to cancel. Shortcuts the system grabs first (e.g. ⌘⇥) can't be recorded.

## Install

Download `Keysy.dmg` from [Releases](https://github.com/jojonki/Keysy/releases), drag Keysy to Applications,
then grant **Accessibility** permission when prompted
(System Settings → Privacy & Security → Accessibility). Keysy needs it to read and send key events.

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
