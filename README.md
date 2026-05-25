# FastNotch

FastNotch is a lightweight native macOS notch utility.

It shows a small floating notch trigger at the top center of the main display. The trigger can open or hide a selected app, with Finder-specific behavior tuned for Spaces and Stage Manager.

## Features

- Native AppKit macOS app
- Accessory app with no Dock icon
- Floating borderless notch trigger
- Hover or click interaction mode
- Menu bar configuration
- Selected app checkmark in menu
- Finder quick action with double hover
- Low idle CPU usage
- No external dependencies

## Build and Run

```bash
./script/build_and_run.sh --install
```

Other modes:

```bash
./script/build_and_run.sh --verify
./script/build_and_run.sh --logs
./script/build_and_run.sh --telemetry
```

## Permissions

FastNotch uses Apple Events to show and hide selected apps. macOS may ask for Automation permission the first time it controls Finder or another app.

## Notes

This project intentionally avoids Sparkle, Lottie, media frameworks, helpers, and heavy background work.
