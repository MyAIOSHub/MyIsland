# My Island 产品需求文档 (PRD)

> 版本：v1.4.4  |  平台：macOS 15.6+  |  Bundle ID：app.myisland.macos

---

## 1. 产品概览

**My Island** 是一款驻留在 macOS 刘海（Notch）区域的状态面板应用，将零散的终端 / 菜单栏交互统一收敛到顶部刘海，提供两大核心能力：

1. **AI 编码 Agent 实时监控与审批**（Claude Code、Codex、Gemini CLI、GitHub Copilot、Antigravity）
2. **全流程会议录制、转写与智能总结**（豆包 Miaoji + 任意 OpenAI 兼容 LLM）

辅以语音输入、剪贴板历史、声音通知、宠物养成等轻量生产力能力。

---

## 2. 问题陈述

**编码场景**：使用 Claude Code / Codex 等 Agent 的开发者，在需要审批工具调用、跟踪并行子任务、处理意外中断时，必须频繁切回终端/IDE，上下文切换代价高，通知容易被淹没。

**会议场景**：跨团队远程会议（含中英混杂与多说话人）需要逐字稿 + 决策摘要 + 待办提取，但现有云转写工具流程割裂，无法将"会议中强调的金句"与"AI 自动生成的结构化摘要"关联起来，也缺乏 macOS 原生的日程 + 提醒闭环。

**共同代价**：注意力被多应用切换碎片化；重要状态（Agent 等待审批、会议开始前 5 分钟）得不到聚焦性的物理提示。

---

## 3. 目标用户

| Persona | 描述 | 主要使用模块 |
|---|---|---|
| **AI-first 开发者** | 每天使用 Claude Code / Codex 等 Agent 写代码，存在多 agent 并行、tool approval 频繁的工作流 | Agent 监控、语音输入、tmux 审批 |
| **跨语种会议主持人 / PM** | 需要中英日韩多语会议记录，输出决策纪要与 TODO | 会议助手、日历提醒 |
| **重度 macOS 用户** | 追求"刘海原生"的信息密度与沉浸感，愿意付出权限与配置代价 | 全量功能、显示定制、宠物 |

---

## 4. 产品目标 (Goals)

1. **G1 · 降低 Agent 审批延迟** — 从终端切到 notch 完成 approve/reject 的时间 ≤ 2 秒；支持 tmux + TTY 直投两条通路，确保成功率 ≥ 99%。
2. **G2 · 端到端会议闭环** — 从开始录音到产出"摘要 + 决策 + 说话人观点 + 金句"四段式文档，全自动无需手工中转，单次 60 分钟会议总处理时间 ≤ 8 分钟。
3. **G3 · 零手工配置的权限引导** — 首次启动按需请求 Accessibility / Microphone / Screen Recording / Calendar / Notifications，无需进入系统设置手动打开。
4. **G4 · 本地可调试、云可替换** — 所有原始载荷 (`memo-*-payload.json`) 落盘可重放；LLM / ASR 端点可通过 UserDefaults 或环境变量替换为任意 OpenAI 兼容服务。
5. **G5 · 多语言首发质量** — 英文、简体中文、日语、韩语四语同步发布，所有面向用户文案均需本地化覆盖。

---

## 5. 非目标 (Non-Goals)

- ❌ **不做 Windows / Linux 版本** — 依赖 macOS Notch 几何与 ScreenCaptureKit / EventKit 专有 API。
- ❌ **不托管用户的 API Key** — 密钥始终存在本地 UserDefaults 或环境变量，不走任何云端代理。
- ❌ **不做通用笔记管理** — 会议归档是产物而非目的，不与 Notion/Obsidian 深度集成。
- ❌ **不取代 IDE** — 只做 Agent 状态面板，不做代码编辑 / diff 审阅。
- ❌ **不做跨设备同步** — 会议档案、宠物、设置均本地保存，不做 iCloud / 账户体系。

---

## 6. 用户故事

### 6.1 AI-first 开发者

- 作为使用 Claude Code 的开发者，我希望工具调用请求出现在刘海，**不必 alt-tab 回终端**即可一键批准/拒绝。
- 作为同时跑多个 subagent 的开发者，我希望**每个 agent 的实时工具执行**在刘海可见，避免某个 agent 卡死被忽略。
- 作为用户，我希望当 Agent session 被 `.interrupt` 时刘海立刻反映"已中断"，**而不是假装仍在运行**。
- 作为用户，我希望终端聚焦时声音通知自动静音，**避免打扰我正在查看的日志**。

### 6.2 会议主持人 / PM

- 作为开会人，我希望麦克风 + 系统声音**同时被录入一条 16kHz WAV**，这样远程 Zoom 对端也能转写。
- 作为说中英文的团队，我希望实时转写**按说话人分段**显示（`enable_speaker_info`），并在会后按人整理观点。
- 作为会中想"标重点"的用户，我希望用一个快捷键 / 按钮把当前段落标为 **focus/note**，会后自动变成"金句"卡片。
- 作为 PM，我希望会议结束自动产出**决策 (decisions) + 各说话人观点 + Todo + Q&A**，决策含提议人和时间戳。
- 作为有日程的用户，我希望"安排的会议"自动写入 macOS Calendar，并在**开始前 5 分钟 + 准点**两次提醒我（刘海展开 + 系统通知）。
- 作为用户，我希望能**把已有的 mp4 / m4a 上传**到 hub，跑一遍同样的 Miaoji + LLM 管道。

### 6.3 通用体验

- 作为用户，我希望按住 **Fn** 即可语音输入；终端窗口走 Apple SFSpeech 本地识别，非终端走云端 ASR。
- 作为多显示器用户，我希望在设置里**指定面板所在的显示器**，并选 Clean / Detailed 两种密度。
- 作为用户，我希望通过 Sparkle **自动更新**，无需手动重下 DMG。

---

## 7. 功能需求

### 7.1 P0 · Agent 监控

| ID | 需求 | 验收标准 |
|---|---|---|
| A1 | 多 Agent session 追踪 | Hooks 部署在 `~/.claude/hooks/`、`~/.codex/hooks/`、`~/.gemini/hooks/`、`~/.github-copilot/hooks/`；socket server 接收事件 |
| A2 | 刘海工具审批 | Approve / Always-approve / Reject 三按钮；tmux 注入失败时 TTY 直投兜底 |
| A3 | Subagent 任务扇出 | 每 agent 独立 JSONL 文件监听，子任务在同一 session 卡片内流式展开 |
| A4 | 中断检测 | JSONL 出现 `.interrupt` 状态后 1 秒内 UI 更新为"已中断" |

### 7.2 P0 · 会议助手（v1.4.4+）

| ID | 需求 | 验收标准 |
|---|---|---|
| M1 | 流式 ASR | 通过 WebSocket 连接豆包 bigmodel (`wss://.../api/v3/sauc/bigmodel_async`)，resource `volc.bigasr.sauc.duration`；句级聚合按说话人展示 |
| M2 | 混音采集 | 麦克风 + 系统音（ScreenCaptureKit）合流为 16kHz / 16-bit 单流，本地落盘 WAV |
| M3 | Memo 总结管线 | Miaoji `/api/v3/auc/lark/{submit,query}` 生成 full summary + 章节 + todo + Q&A；原始 `memo-*-payload.json` 全部落盘 |
| M4 | LLM 增强 | 任意 OpenAI 兼容端点生成：**决策**（含 rationale/proposer/timecode）+ **各说话人观点**（1–3 条立场）+ 基于用户 focus/note 的正文加粗 |
| M5 | 金句区 | 用户在录音中标记的每条 `focus` / `note` 渲染为引用卡片，附说话人名 |
| M6 | 定时会议 | EventKit write-only（macOS 14+ API）写入日历；内嵌两段式提醒（-5 分钟 + 准点），刘海展开 + 本地通知 |
| M7 | 上传转写 | 拖拽音频/视频 → 上传 TOS → 走 Miaoji 全流程；支持历史 payload 重新解析 |

### 7.3 P1 · 输入与 UX

| ID | 需求 | 验收标准 |
|---|---|---|
| I1 | 语音输入 (Fn) | 终端窗口：Apple SFSpeech 本地识别；非终端：云端 ASR；识别结果粘贴到当前焦点 |
| I2 | 剪贴板历史 | 刘海展示最近 N 条；点击即复制 |
| I3 | 声音通知 | 分类开关 + 音量；终端聚焦时自动 suppress |
| I4 | 宠物 Gacha | 程序化生成的宠物作为刘海 icon；抽取/更换流程 |
| I5 | 显示定制 | Clean / Detailed 两种布局；字号、面板尺寸、显示器选择 |

### 7.4 P1 · 系统能力

| ID | 需求 | 验收标准 |
|---|---|---|
| S1 | Sparkle 自动更新 | EdDSA 签名；对照 GitHub Releases appcast |
| S2 | 多语言 | en / zh-Hans / ja / ko 四语 Strings 100% 覆盖 |
| S3 | Mixpanel 遥测 | 可在设置关闭；无 PII |
| S4 | 权限首启引导 | 6 项权限首次触发时按需弹出，无需进系统设置 |

### 7.5 P2 · 未来考虑（前瞻设计但不开发）

- Windows Runtime 伪 Notch / Linux 顶栏适配（架构上把 Notch 几何抽象到 `Core/Geometry`，为未来插件化留出口）
- 会议归档的云同步（保持 payload 结构版本化，方便未来迁移）
- 自定义 Agent 接入 SDK（hooks 当前 hard-coded 四种 agent，未来外部化配置）

---

## 8. 技术架构

### 8.1 模块划分

```
App/          入口、AppDelegate、WindowManager、ScreenObserver
Core/         Settings、Geometry、NotchViewModel（面板核心状态）
Events/       全局事件监控
Models/       Meeting（MeetingModels / ArchiveModels / LiveTimeline）等
Services/
  Chat/       聊天历史
  Hooks/      CLI hook + socket server
  Meeting/    Coordinator、DoubaoStreamingASRClient、MeetingMemoClient、
              MeetingSummaryEngine、MeetingCalendarService、
              MeetingScheduleReminder、MeetingAudioCaptureCoordinator
  Pet/        Gacha
  Session/    Agent session 监控
  Shared/     进程工具
  Sound/      声音
  State/      状态管理与文件同步
  Tmux/       tmux 集成 + tool approval
  Update/     Sparkle
  Voice/      麦克风 + STT + Dashscope ASR
  Window/     窗口寻找 / Yabai
UI/           Components（MarkdownRenderer、tiles、pickers）+ Views（Meeting、Settings、Sound…）
Utilities/
Resources/    Entitlements、Info.plist、本地化、声音、MeetingAgentPack
```

### 8.2 关键依赖

- **Sparkle** — 自动更新
- **swift-markdown** — 转写/摘要渲染
- **json-logic-swift** — 建议规则评估
- **Mixpanel** — 可选遥测

### 8.3 配置与密钥

所有会议相关密钥均在 `Meeting Hub → Settings`，**解析顺序**：存储偏好 → 环境变量 → 硬编码默认值。

主要 keys：`meeting.doubao.streaming.{endpoint,appID,accessToken,resourceID}`、`meeting.doubao.memo.{submitURL,queryURL,accessToken}`、`meeting.agent.{baseURL,apiKey,model}`。

敏感凭证推荐 `launchctl setenv MEETING_AGENT_API_KEY "..."` 以便 GUI 启动时继承。

---

## 9. 成功指标

### 9.1 领先指标（launch 后 1–4 周）

| 指标 | 目标 | 测量方式 |
|---|---|---|
| Agent 审批完成中位时延 | ≤ 2s | Mixpanel 事件 `agent.tool.approve` timestamp 差 |
| 会议端到端成功率 | ≥ 95% | 每次录音的 submit → query → LLM enhance 成功链条占比 |
| 首启权限通过率 | 6 项权限 ≥ 90% 全通过 | `permission.granted` / `requested` |
| 首启到第一次完成会议 | ≤ 10 分钟 | funnel `install → first meeting archive` |
| Crash-free session | ≥ 99.5% | Sparkle + Mixpanel |

### 9.2 滞后指标（1 季度）

- 周活跃用户使用 ≥ 2 个核心模块的比例 ≥ 40%
- Sparkle 升级到最新版渗透率 ≥ 70%（发布后 2 周内）
- GitHub Release DMG 下载 → 实际 launch 转化率 ≥ 60%

---

## 10. 约束与依赖

- **macOS 版本** — 15.6 为构建目标；EventKit write-only 与 ScreenCaptureKit 在 14+ 可用，但 project target 固定 15.6。
- **Xcode 16+** 构建。
- **外部服务** — 豆包 bigmodel（流式 ASR）、Miaoji（总结）、任一 OpenAI 兼容 LLM。无兜底服务，端点或密钥缺失时会议模块整体不可用。
- **分发** — 必须走 `notarytool` keychain profile `MyIsland` + Sparkle EdDSA 密钥；CI 之外的本地发布通过 `./scripts/create-release.sh` 一键串联。

---

## 11. 未决问题

| 问题 | 负责角色 | 是否阻塞 |
|---|---|---|
| v1.5 是否把 Hooks agent 列表外部化为 JSON 配置？ | 工程 | 否 |
| 会议归档是否需要本地加密（含转写与原始 WAV）？ | 安全 / 产品 | 否，但影响企业版 |
| LLM 增强失败时是否展示"降级总结"还是整体失败？ | 产品 | 是，影响 M4 验收边界 |
| 多显示器下刘海状态跨屏迁移动画是否由 `Core/Geometry` 统一？ | 工程 | 否 |
| 宠物 Gacha 是否保留（与生产力定位的冲突）？ | 产品 | 否 |

---

## 12. 时间线考量

- **v1.4.x（当前）** — 会议模块稳定化：金句区、LLM 决策 / 观点、历史 payload 重解析、Miaoji 提取修复。
- **v1.5（下季度候选）** — Hooks agent 外部化；会议归档搜索；LLM 增强失败降级策略。
- **v2.0（长线）** — 插件化 Agent 接入；企业版（本地加密 + 团队模板）。

---

## 13. 发布与运营

- 构建：`./scripts/build.sh`（archive + 签名 .app）
- 发布：`./scripts/create-release.sh`（公证 + DMG + Sparkle 签名 + GitHub Release + appcast）
- 密钥生成：`./scripts/generate-keys.sh`
- 分发：GitHub Releases（`MyIsland-<version>.dmg`），用户侧 Sparkle 自升级。

---

*文档版本：基于 v1.4.4 代码库，2026-04-17 整理。*
