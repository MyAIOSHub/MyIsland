# My Island

macOS Notch Status Panel - Agent monitoring and notification app.

## Project Structure

```
MyIsland.xcodeproj/          # Xcode project (SPM dependencies)
MyIsland/                    # Source code (auto-synced by Xcode)
  App/                       # App entry point, delegates, window management
    MyIslandApp.swift        # @main entry point
    AppDelegate.swift
    WindowManager.swift
    ScreenObserver.swift
  Core/                      # Core logic (settings, geometry, view models)
  Events/                    # Event monitoring
  Models/                    # Data models
  Services/                  # Business logic
    Chat/                    # Chat history
    Hooks/                   # CLI hook integration (socket server)
    Pet/                     # Pet gacha system
    Session/                 # Agent session monitoring
    Shared/                  # Process utilities
    Sound/                   # Sound playback
    State/                   # State management, file sync
    Tmux/                    # Tmux integration, tool approval
    Update/                  # Sparkle auto-update
    Voice/                   # Voice input (mic + speech recognition)
    Window/                  # Window finder/focuser, Yabai
  UI/                        # SwiftUI views
    Components/              # Reusable components
    Views/                   # View implementations
    Window/                  # NotchWindow controllers
  Utilities/                 # Helpers
  Resources/                 # Entitlements, sounds, images, localization, fonts
  Assets.xcassets/           # App icon, colors
  Info.plist                 # App configuration
scripts/                     # Build and release scripts
```

## Key Info

- **Bundle ID:** app.myisland.macos
- **Product Name:** My Island
- **Min macOS:** 15.6
- **Swift Version:** 5.0
- **Dependencies:** Sparkle (auto-update), Mixpanel (analytics), swift-markdown, json-logic-swift
- **Languages:** en, zh-Hans, ja, ko
- **Build:** `xcodebuild -scheme MyIsland -configuration Release`
- **Launch command:** `pkill -9 -f "My Island"; xattr -cr ~/Library/Developer/Xcode/DerivedData/MyIsland-*/Build/Products/Debug/My\ Island.app && open ~/Library/Developer/Xcode/DerivedData/MyIsland-*/Build/Products/Debug/My\ Island.app`

@AGENTS.md

# Rule

1. 当你要写入内容到 Claude.md 时，写入对象变为 AGENTS.md
