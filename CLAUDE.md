# My Island

macOS Notch Status Panel - Agent monitoring and notification app.

## Project Structure

```
My Island.app/              # macOS app bundle
  Contents/
    Info.plist              # App configuration (bundle ID: app.myisland.macos)
    MacOS/my-island         # Main executable (Universal Binary: x86_64 + arm64)
    Helpers/my-island-bridge  # Helper executable
    Frameworks/
      Sentry.framework      # Error reporting
      Sparkle.framework     # Auto-update
    Resources/
      AppIcon.icns          # App icon
      Fonts/                # Custom fonts (DepartureMono)
      Sounds/               # Audio assets
      en.lproj/             # English localization
      zh-Hans.lproj/        # Simplified Chinese localization
      ja.lproj/             # Japanese localization
      ko.lproj/             # Korean localization
    _CodeSignature/         # Code signing resources
```

## Key Info

- **Bundle ID:** app.myisland.macos
- **Min macOS:** 14.0
- **Version:** 1.0.18
- **Type:** Menu bar app (LSUIElement)
- **Languages:** en, zh-Hans, ja, ko
