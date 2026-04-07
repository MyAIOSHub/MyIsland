# My Island

macOS Notch Status Panel for monitoring AI coding agents.

My Island lives in your Mac's notch area, providing real-time status updates, notifications, and controls for Claude Code, Codex, Gemini CLI, Copilot, and other AI coding agents.

## Features

- **Agent Session Monitoring** - Track active Claude Code / Codex / Gemini / Copilot sessions in real time
- **Notch Integration** - Compact status display that fits naturally in the macOS notch
- **CLI Hook System** - Automatic hook installation for supported CLI tools
- **Voice Input** - Press Fn to dictate, transcription is pasted into the active input field
- **Tool Approval** - Review and approve/reject tool calls from the notch panel
- **Sound Notifications** - Configurable sounds for session events
- **Display Settings** - Adjustable panel size, layout modes (clean / detailed), font size
- **Pet Gacha** - Collect cute companions for your notch
- **Auto Update** - Built-in Sparkle updater
- **Multilingual** - English, Simplified Chinese, Japanese, Korean

## Requirements

- macOS 15.6+
- Xcode 16+ (for building from source)

## Build

```bash
xcodebuild -scheme MyIsland -configuration Release
```

## Run (Debug)

```bash
xcodebuild -scheme MyIsland -configuration Debug
pkill -9 -f "My Island"
xattr -cr ~/Library/Developer/Xcode/DerivedData/MyIsland-*/Build/Products/Debug/My\ Island.app
open ~/Library/Developer/Xcode/DerivedData/MyIsland-*/Build/Products/Debug/My\ Island.app
```

## Project Structure

```
MyIsland.xcodeproj/          # Xcode project (SPM dependencies)
MyIsland/                    # Source code
  App/                       # App entry point, delegates, window management
  Core/                      # Settings, geometry, view models
  Events/                    # Event monitoring
  Models/                    # Data models
  Services/                  # Business logic
    Chat/                    # Chat history
    Hooks/                   # CLI hook integration
    Pet/                     # Pet gacha system
    Session/                 # Agent session monitoring
    Sound/                   # Sound playback
    State/                   # State management, file sync
    Tmux/                    # Tmux integration, tool approval
    Voice/                   # Voice input (mic + speech recognition)
    Window/                  # Window finder/focuser
  UI/                        # SwiftUI views
    Components/              # Reusable components
    Views/                   # View implementations
    Window/                  # NotchWindow controllers
  Utilities/                 # Helpers
  Resources/                 # Entitlements, sounds, images, localization, fonts
scripts/                     # Build and release scripts
```

## Dependencies

- [Sparkle](https://github.com/sparkle-project/Sparkle) - Auto-update framework
- [swift-markdown](https://github.com/apple/swift-markdown) - Markdown parsing
- [json-logic-swift](https://github.com/nicklama/json-logic-swift) - JSON Logic evaluation

## Permissions

My Island requires the following permissions:

| Permission | Purpose |
|---|---|
| Accessibility | Paste voice transcription into active apps |
| Microphone | Voice input via Fn key |
| Speech Recognition | Convert voice to text |

## License

See [LICENSE.md](LICENSE.md) for details.
