# My Island

macOS Notch Status Panel for monitoring AI coding agents **and running full-featured meeting recording**.

My Island lives in your Mac's notch area, providing real-time status updates, notifications, and controls for Claude Code, Codex, Gemini CLI, Copilot, and other AI coding agents — plus a streaming meeting transcription and summarisation workflow powered by Doubao (豆包) Miaoji.

## Install

### Pre-built

1. Download **`MyIsland-<version>.dmg`** from the [latest release](https://github.com/MyAIOSHub/MyIsland/releases/latest).
2. Open the DMG and drag **My Island** to **Applications**.
3. Launch from Applications — the icon appears in the menu bar notch area.

### Build from source

```bash
git clone https://github.com/MyAIOSHub/MyIsland.git
cd MyIsland
xcodebuild -scheme MyIsland -configuration Release
```

For local debug runs:

```bash
xcodebuild -scheme MyIsland -configuration Debug
pkill -9 -f "My Island"
xattr -cr ~/Library/Developer/Xcode/DerivedData/MyIsland-*/Build/Products/Debug/My\ Island.app
open ~/Library/Developer/Xcode/DerivedData/MyIsland-*/Build/Products/Debug/My\ Island.app
```

---

## Features

### Agent monitoring

- **Multi-agent session tracking** — Claude Code, Codex, Gemini CLI, GitHub Copilot, Antigravity (VS Code). Hooks live in `~/.claude/hooks/`, `~/.codex/hooks/`, `~/.gemini/hooks/`, `~/.github-copilot/hooks/`.
- **Tool approval from the notch** — approve / always-approve / reject tool calls without leaving the menu bar (tmux + TTY-direct fallback).
- **Subagent task fan-out** — per-agent JSONL file watchers surface live tool execution for parallel subagents.
- **Interrupt detection** — JSONL session files are watched for `.interrupt` status so dropped sessions don't appear stuck.

### Meeting Assistant (v1.4.4+)

- **Streaming transcription** — Doubao bigmodel real-time ASR over WebSocket, with live sentence-level aggregation per speaker and multi-speaker diarisation (`enable_speaker_info`, resource `volc.bigasr.sauc.duration`).
- **Mixed audio capture** — Microphone + system audio (ScreenCaptureKit) merged into a 16 kHz/16-bit stream; WAV archive written locally.
- **Post-meeting summary pipeline** — Doubao Miaoji (`/api/v3/auc/lark/{submit,query}`) produces full summary, chapter summaries, todo extraction and Q&A extraction. All raw payloads (`memo-*-payload.json`) are written to disk for debuggability and re-parsing.
- **LLM enhancement pass** — any OpenAI-compatible endpoint (Ark Doubao, Qwen, DeepSeek…) augments the summary with:
  - **决策 (decisions)** — concrete conclusions with rationale, proposer and timecode.
  - **各说话人观点 (per-speaker viewpoints)** — 1–3 bullet stance per speaker.
  - Bold-weighting of passages tied to user highlights / notes in the final summary.
- **金句 (quote highlights) section** — every `focus` / `note` annotation the user marked during recording is rendered as a quote-styled card with speaker attribution.
- **Scheduled meetings** — write to the macOS Calendar (EventKit write-only access, macOS 14+ API). Two-stage in-process reminder (5 min before + on-time) expands the notch and delivers a local notification.
- **Upload-then-transcribe** — drop an existing audio/video file into the hub; it's uploaded to TOS and handed to Miaoji for full transcription + summary.

### Input / UX

- **Voice Input** — press Fn to dictate; Apple SFSpeech for terminals, cloud ASR post-processing for non-terminals, paste into the active field.
- **Clipboard history** — the notch surfaces recent clipboard entries.
- **Sound notifications** — per-category toggles, volume control, suppress-when-terminal-focused.
- **Pet Gacha** — collect procedurally generated pets for the notch icon.
- **Display settings** — Clean / Detailed layouts, font size, panel dimensions, monitor picker.
- **Auto-update** — built-in Sparkle updater against the GitHub Releases appcast.
- **Multilingual** — English, 简体中文, 日本語, 한국어.

---

## Requirements

- macOS **15.6+** (the ASR + Memo pipelines rely on EventKit / ScreenCaptureKit APIs that ship with 14+, but the project target is 15.6).
- Xcode **16+** for building from source.

---

## Permissions

| Permission | Purpose |
|---|---|
| Accessibility | Paste voice transcription into active apps |
| Microphone | Voice input + meeting recording |
| Speech Recognition | On-device STT for terminal-targeted voice input |
| Screen Recording | Capture system audio for meetings via ScreenCaptureKit |
| Calendar (Write) | Sync scheduled meetings to Apple Calendar |
| Notifications | On-time reminders for scheduled meetings |

The first run prompts for each — no manual System Settings edit required.

---

## Configuration

Meeting-assistant integrations are configured under **Meeting Hub → Settings**. Credentials can also be supplied via **environment variables** so nothing sensitive lands in the preferences plist or source control:

| Purpose | UserDefaults key | Env var | Default |
|---|---|---|---|
| Streaming ASR endpoint | `meeting.doubao.streaming.endpoint` | — | `wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async` |
| Streaming ASR app ID | `meeting.doubao.streaming.appID` | — | — |
| Streaming ASR access token | `meeting.doubao.streaming.accessToken` | — | — |
| Streaming ASR resource ID | `meeting.doubao.streaming.resourceID` | — | `volc.bigasr.sauc.duration` |
| Memo submit URL | `meeting.doubao.memo.submitURL` | — | `https://openspeech.bytedance.com/api/v3/auc/lark/submit` |
| Memo query URL | `meeting.doubao.memo.queryURL` | — | `https://openspeech.bytedance.com/api/v3/auc/lark/query` |
| Memo access token | `meeting.doubao.memo.accessToken` | — | — |
| LLM base URL | `meeting.agent.baseURL` | `MEETING_AGENT_BASE_URL` | `https://ark.cn-beijing.volces.com/api/v3` |
| LLM API key | `meeting.agent.apiKey` | `MEETING_AGENT_API_KEY` | — |
| LLM model | `meeting.agent.model` | `MEETING_AGENT_MODEL` | `doubao-1-5-pro-32k-250115` |

Env-var resolution order: stored prefs → environment → hard-coded default.

Set persistent env vars for GUI launches with `launchctl setenv`:

```bash
launchctl setenv MEETING_AGENT_API_KEY "your-key-here"
echo 'export MEETING_AGENT_API_KEY="your-key-here"' >> ~/.zshenv
```

---

## Project structure

```
MyIsland.xcodeproj/          # Xcode project (SPM dependencies)
MyIsland/
  App/                       # Entry point, AppDelegate, window manager, screen observer
  Core/                      # Settings, geometry, NotchViewModel
  Events/                    # Event monitoring
  Models/
    Meeting/                 # MeetingModels, MeetingArchiveModels, MeetingLiveTimeline
  Services/
    Chat/                    # Chat history
    Hooks/                   # CLI hook integration, socket server
    Meeting/                 # Coordinator, DoubaoStreamingASRClient, DoubaoStreamingProtocol,
                             # MeetingMemoClient, MeetingSummaryEngine, MeetingCalendarService,
                             # MeetingScheduleReminder, MeetingAudioCaptureCoordinator, etc.
    Pet/                     # Pet gacha system
    Session/                 # Agent session monitoring
    Shared/                  # Process utilities
    Sound/                   # Sound playback
    State/                   # State management, file sync
    Tmux/                    # Tmux integration, tool approval
    Update/                  # Sparkle auto-update
    Voice/                   # Voice input (mic + STT + Dashscope ASR)
    Window/                  # Window finder/focuser, Yabai
  UI/
    Components/              # Reusable components (MarkdownRenderer, tiles, pickers)
    Views/
      Meeting/               # MeetingHubView, MeetingLiveView, MeetingDetailView,
                             # MeetingSettingsView
      …                      # Settings, Sound, Notch menu, etc.
    Window/                  # NotchWindow controllers
  Utilities/
  Resources/                 # Entitlements, Info.plist, localizations, sounds, MeetingAgentPack
scripts/                     # build.sh, create-release.sh, generate-keys.sh
```

---

## Dependencies

- [Sparkle](https://github.com/sparkle-project/Sparkle) — auto-update
- [swift-markdown](https://github.com/apple/swift-markdown) — markdown rendering in transcripts / summaries
- [json-logic-swift](https://github.com/nicklama/json-logic-swift) — advice rule evaluation
- [Mixpanel](https://github.com/mixpanel/mixpanel-swift) — analytics (disable in settings)

---

## Release

The release script handles notarisation, DMG creation, Sparkle signing, GitHub upload and appcast generation in one go:

```bash
./scripts/build.sh          # archive + export signed .app
./scripts/create-release.sh # notarise + DMG + Sparkle sign + GitHub release + appcast
```

A `notarytool` keychain profile named `MyIsland` and a Sparkle EdDSA key under `.sparkle-keys/` are required — see `scripts/generate-keys.sh` and the prompts in `create-release.sh`.

---

## License

See [LICENSE.md](LICENSE.md) for details.
