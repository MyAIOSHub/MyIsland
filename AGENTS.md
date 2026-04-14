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

## Skill-Driven Development (MUST FOLLOW)

All non-trivial work MUST proactively adopt the installed skills and delegate execution to subagents. This is mandatory, not optional.

### Installed Skill Plugins

| Plugin | Key Skills |
|--------|-----------|
| **superpowers** | brainstorming, writing-plans, executing-plans, test-driven-development, systematic-debugging, subagent-driven-development, dispatching-parallel-agents, verification-before-completion, requesting-code-review, using-git-worktrees |
| **compound-engineering** | ce:brainstorm, ce:plan, ce:work, ce:review, ce:debug, ce:compound, git-commit-push-pr, document-review, frontend-design, test-xcode |
| **agent-skills** | spec-driven-development, planning-and-task-breakdown, incremental-implementation, test-driven-development, code-review-and-quality, debugging-and-error-recovery, security-and-hardening, performance-optimization, api-and-interface-design |

### Workflow Rules

1. **Requirement Analysis Phase** — When receiving a new feature or task:
   - Invoke `superpowers:brainstorming` or `ce:brainstorm` to explore requirements before coding
   - Invoke `superpowers:writing-plans` or `ce:plan` to produce a structured implementation plan
   - For specs, invoke `agent-skills:spec-driven-development`

2. **Execution Phase** — When implementing:
   - **MUST use subagents** (Agent tool) to parallelize independent work streams
   - Invoke `superpowers:subagent-driven-development` or `superpowers:dispatching-parallel-agents` to coordinate
   - Each subagent should invoke the appropriate skill for its task:
     - Coding → `superpowers:test-driven-development` or `agent-skills:incremental-implementation`
     - Debugging → `superpowers:systematic-debugging` or `ce:debug`
     - UI work → `compound-engineering:frontend-design` or `agent-skills:frontend-ui-engineering`
     - API design → `agent-skills:api-and-interface-design`
   - Use worktrees (`superpowers:using-git-worktrees`) for isolated parallel branches when appropriate

3. **Verification Phase** — Before claiming completion:
   - Invoke `superpowers:verification-before-completion` to run checks with evidence
   - Invoke `superpowers:requesting-code-review` or `ce:review` for self-review
   - Invoke `agent-skills:code-review-and-quality` via a subagent for independent review
   - Invoke `agent-skills:security-and-hardening` if the change touches user input or external data

4. **Shipping Phase** — When committing/PR:
   - Use `compound-engineering:git-commit-push-pr` for commit + PR in one step
   - Invoke `agent-skills:git-workflow-and-versioning` for branch management

### Subagent Delegation Pattern

```
Main Agent (coordinator)
  ├── Subagent A → skill: brainstorming / planning
  ├── Subagent B → skill: test-driven-development (write tests)
  ├── Subagent C → skill: incremental-implementation (write code)
  ├── Subagent D → skill: code-review-and-quality (review)
  └── Subagent E → skill: verification-before-completion (verify)
```

- Spawn subagents for ANY task that can run independently
- Each subagent must invoke the Skill tool with the relevant skill name before starting its work
- The main agent coordinates, reviews subagent output, and handles integration
- Prefer parallel subagents over sequential execution whenever possible
