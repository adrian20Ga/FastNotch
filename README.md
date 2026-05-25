# FastNotch

FastNotch is a small native macOS utility for people who want quick access to Finder without letting Finder take over their workflow.

It adds a minimal floating trigger at the top center of the screen, near the notch area. Use it to show or hide Finder, Chrome, Notes, Terminal, or another selected app from the menu bar.

The main use case is Stage Manager: open Finder when you need it, dismiss it when you are done, and return to the app you were working in.

## Why

Opening Finder manually can be annoying when Stage Manager is enabled:

- Finder can become its own Stage Manager group.
- Minimizing or hiding Finder breaks flow.
- Re-opening Finder can jump to another Desktop or Space.
- Repeated Finder opens can leave extra windows around.

FastNotch tries to make Finder feel temporary: open, use, dismiss, go back.

## Features

- Native AppKit macOS app
- No Dock icon
- Small floating notch trigger
- Menu bar settings
- Hover mode and click mode
- Selected app checkmark in the menu
- Finder-specific behavior for Spaces and Stage Manager
- Double-hover Finder quick action
- Hides apps instead of quitting them
- No external dependencies
- Low idle CPU usage

## Default Apps

FastNotch includes menu presets for:

- Finder
- Chrome
- Safari
- Notes
- Terminal
- Settings

You can also choose a custom app or shortcut from the menu.

## How It Works

FastNotch has two interaction modes:

### Open on Hover

This is the default mode.

- Hover the notch trigger once to show the selected app.
- Hover it again to hide the selected app.
- Double-hover quickly to open Finder as a quick action.
- Double-hover again to dismiss that Finder window.

### Open on Click

- Click the notch trigger to show the selected app.
- Click it again to hide the selected app.

## Finder Behavior

Finder gets special handling because it behaves differently from normal apps on macOS.

FastNotch checks whether Finder has a visible window in the current Space:

- If Finder is already visible in the current Space, FastNotch activates it.
- If Finder is not visible in the current Space, FastNotch creates one Finder window there.
- When dismissed from FastNotch, the Finder window is closed so windows do not pile up.
- After dismissing Finder, FastNotch attempts to return focus to the app you were using before.

## Other Apps

For apps like Chrome, Safari, Notes, and Terminal:

- FastNotch opens or activates the app.
- When dismissed, FastNotch hides the app instead of quitting it.
- The app session remains loaded.
- FastNotch attempts to return focus to the app you were using before.

## Build and Run

Clone the repository, then run:

```bash
./script/build_and_run.sh --install
```

This builds the app, stages an app bundle, installs it to `/Applications/FastNotch.app`, and launches it.

Other useful commands:

```bash
./script/build_and_run.sh --verify
./script/build_and_run.sh --logs
./script/build_and_run.sh --telemetry
```

## Permissions

macOS may ask for Automation permission the first time FastNotch controls Finder or another app.

FastNotch uses Apple Events only to show, hide, activate, or close the selected app window. It does not install helpers, login items, updaters, or background services.

## Design Goals

- Stay small.
- Stay native.
- Avoid background work.
- Avoid heavy frameworks.
- Avoid music, calendar, shelves, visualizers, HUDs, and unrelated features.
- Keep Finder access fast and reversible.

## Limitations

Stage Manager and Spaces are controlled by macOS. FastNotch avoids forcing unnecessary app activation when possible, but macOS may still decide how windows are grouped or surfaced.

Double-hover Finder quick action is designed to reduce Stage Manager disruption, but exact behavior can vary by macOS version and current window state.
