# UnNatural

UnNatural is a macOS menu bar app that reverses scroll direction separately for mouse and trackpad.

## Features

- Lives in the macOS menu bar
- Reverses mouse scrolling when `Mouse` is enabled
- Reverses trackpad scrolling when `Trackpad` is enabled
- Supports launch at login
- Opens the Accessibility permission screen from Settings

## Requirements

- macOS
- Xcode
- Accessibility permission for `UnNatural.app`

## Build And Install

Clone the repository and install the app into `/Applications`.

```bash
git clone https://github.com/jedipunkz/UnNatural.git
cd UnNatural
make install
```

Launch it:

```bash
open /Applications/UnNatural.app
```

Or build, install, and launch in one command:

```bash
make open
```

## First Run

1. Open `UnNatural.app`.
2. Click the UnNatural menu bar icon.
3. Choose `Settings...`.
4. Click `Open Permission`.
5. Enable `UnNatural` in `Privacy & Security > Accessibility`.
6. Enable `Mouse` and/or `Trackpad`.

If scrolling does not change immediately, quit and reopen `UnNatural.app` after granting Accessibility permission.

## Make Targets

```bash
make build    # Build into .DerivedData
make install  # Build and copy UnNatural.app to /Applications
make open     # Build, install, and launch
make clean    # Clean Xcode build products
```

## Distribution Note

UnNatural uses low-level macOS input event handling and requires Accessibility permission. It is intended for direct distribution, for example via GitHub Releases or Homebrew Cask, rather than the Mac App Store.
