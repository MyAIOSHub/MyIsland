//
//  ToolEventProcessor.swift
//  MyIsland
//
//  Handles tool and subagent event processing logic.
//  Extracted from SessionStore to reduce complexity.
//

import Foundation
import os.log

/// Logger for tool events
private let logger = Logger(subsystem: "com.myisland", category: "ToolEvents")

/// Processes tool-related events and updates session state
enum ToolEventProcessor {

    // MARK: - Tool Tracking

    /// Process PreToolUse event for tool tracking
    static func processPreToolUse(
        event: HookEvent,
        session: inout SessionState
    ) {
        guard let toolUseId = event.toolUseId, let toolName = event.tool else { return }

        session.toolTracker.startTool(id: toolUseId, name: toolName)

        // Add to tool history for activity timeline
        let inputSummary = formatToolInputSummary(toolName: toolName, input: event.toolInput)
        let execution = ToolExecution(
            toolUseId: toolUseId,
            toolName: toolName,
            toolInput: inputSummary,
            startedAt: Date()
        )
        session.toolHistory.append(execution)
        // Keep history bounded to last 50 entries
        if session.toolHistory.count > 50 {
            session.toolHistory.removeFirst(session.toolHistory.count - 50)
        }

        let toolExists = session.chatItems.contains { $0.id == toolUseId }
        if !toolExists {
            let input = extractToolInput(from: event.toolInput)
            let placeholderItem = ChatHistoryItem(
                id: toolUseId,
                type: .toolCall(ToolCallItem(
                    name: toolName,
                    input: input,
                    status: .running,
                    result: nil,
                    structuredResult: nil,
                    subagentTools: []
                )),
                timestamp: Date()
            )
            session.chatItems.append(placeholderItem)
            logger.debug("Created placeholder tool entry for \(toolUseId.prefix(16), privacy: .public)")
        }
    }

    /// Process PostToolUse event for tool tracking
    static func processPostToolUse(
        event: HookEvent,
        session: inout SessionState
    ) {
        guard let toolUseId = event.toolUseId else { return }

        session.toolTracker.completeTool(id: toolUseId, success: true)
        updateToolStatus(in: &session, toolId: toolUseId, status: .success)

        // Mark tool execution as completed in history
        if let index = session.toolHistory.lastIndex(where: { $0.toolUseId == toolUseId }) {
            session.toolHistory[index].completedAt = Date()
            // Add brief result summary
            session.toolHistory[index].result = formatToolResultSummary(
                toolName: event.tool,
                toolUseId: toolUseId,
                session: session
            )
        }
    }

    // MARK: - Subagent Tracking

    /// Process PreToolUse event for subagent tracking
    static func processSubagentPreToolUse(
        event: HookEvent,
        session: inout SessionState
    ) {
        guard let toolUseId = event.toolUseId else { return }

        if event.tool == "Task" {
            session.subagentState.startTask(taskToolId: toolUseId)
            logger.debug("Started Task subagent tracking: \(toolUseId.prefix(12), privacy: .public)")
        } else if let toolName = event.tool, session.subagentState.hasActiveSubagent {
            logger.debug("Adding subagent tool \(toolName, privacy: .public) to active Task")
            let input = extractToolInput(from: event.toolInput)
            let subagentTool = SubagentToolCall(
                id: toolUseId,
                name: toolName,
                input: input,
                status: .running,
                timestamp: Date()
            )
            session.subagentState.addSubagentTool(subagentTool)
        }
    }

    /// Process PostToolUse event for subagent tracking
    static func processSubagentPostToolUse(
        event: HookEvent,
        session: inout SessionState
    ) {
        guard let toolUseId = event.toolUseId else { return }

        if event.tool == "Task" {
            if let taskContext = session.subagentState.activeTasks[toolUseId] {
                logger.debug("Task completing with \(taskContext.subagentTools.count) subagent tools")
                attachSubagentToolsToTask(
                    session: &session,
                    taskToolId: toolUseId,
                    subagentTools: taskContext.subagentTools
                )
            } else {
                logger.debug("Task completing but no taskContext found for \(toolUseId.prefix(12), privacy: .public)")
            }
            session.subagentState.stopTask(taskToolId: toolUseId)
        } else {
            session.subagentState.updateSubagentToolStatus(toolId: toolUseId, status: .success)
        }
    }

    /// Transfer all active subagent tools before stop/interrupt
    static func transferAllSubagentTools(session: inout SessionState, markAsInterrupted: Bool = false) {
        for (taskId, taskContext) in session.subagentState.activeTasks {
            var tools = taskContext.subagentTools
            if markAsInterrupted {
                for i in 0..<tools.count {
                    if tools[i].status == .running {
                        tools[i].status = .interrupted
                    }
                }
            }
            attachSubagentToolsToTask(
                session: &session,
                taskToolId: taskId,
                subagentTools: tools
            )
        }
        session.subagentState = SubagentState()
    }

    // MARK: - Tool Status Updates

    /// Update tool status in session's chat items
    static func updateToolStatus(
        in session: inout SessionState,
        toolId: String,
        status: ToolStatus
    ) {
        for i in 0..<session.chatItems.count {
            if session.chatItems[i].id == toolId,
               case .toolCall(var tool) = session.chatItems[i].type,
               tool.status == .waitingForApproval || tool.status == .running {
                tool.status = status
                session.chatItems[i] = ChatHistoryItem(
                    id: toolId,
                    type: .toolCall(tool),
                    timestamp: session.chatItems[i].timestamp
                )
                return
            }
        }
        let count = session.chatItems.count
        logger.warning("Tool \(toolId.prefix(16), privacy: .public) not found in chatItems (count: \(count))")
    }

    /// Find the next tool waiting for approval
    static func findNextPendingTool(
        in session: SessionState,
        excluding toolId: String
    ) -> (id: String, name: String, timestamp: Date)? {
        for item in session.chatItems {
            if item.id == toolId { continue }
            if case .toolCall(let tool) = item.type, tool.status == .waitingForApproval {
                return (id: item.id, name: tool.name, timestamp: item.timestamp)
            }
        }
        return nil
    }

    /// Mark all running tools as interrupted
    static func markRunningToolsInterrupted(session: inout SessionState) {
        for i in 0..<session.chatItems.count {
            if case .toolCall(var tool) = session.chatItems[i].type,
               tool.status == .running {
                tool.status = .interrupted
                session.chatItems[i] = ChatHistoryItem(
                    id: session.chatItems[i].id,
                    type: .toolCall(tool),
                    timestamp: session.chatItems[i].timestamp
                )
            }
        }
    }

    // MARK: - Private Helpers

    /// Attach subagent tools to a Task's ChatHistoryItem
    private static func attachSubagentToolsToTask(
        session: inout SessionState,
        taskToolId: String,
        subagentTools: [SubagentToolCall]
    ) {
        guard !subagentTools.isEmpty else { return }

        for i in 0..<session.chatItems.count {
            if session.chatItems[i].id == taskToolId,
               case .toolCall(var tool) = session.chatItems[i].type {
                tool.subagentTools = subagentTools
                session.chatItems[i] = ChatHistoryItem(
                    id: taskToolId,
                    type: .toolCall(tool),
                    timestamp: session.chatItems[i].timestamp
                )
                logger.debug("Attached \(subagentTools.count) subagent tools to Task \(taskToolId.prefix(12), privacy: .public)")
                break
            }
        }
    }

    /// Format a concise tool input summary for the activity timeline
    private static func formatToolInputSummary(toolName: String, input: [String: AnyCodable]?) -> String? {
        guard let input = input else { return nil }

        switch toolName {
        case "Edit":
            if let path = input["file_path"]?.value as? String {
                return URL(fileURLWithPath: path).lastPathComponent
            }
        case "Write":
            if let path = input["file_path"]?.value as? String {
                return URL(fileURLWithPath: path).lastPathComponent
            }
        case "Read":
            if let path = input["file_path"]?.value as? String {
                return URL(fileURLWithPath: path).lastPathComponent
            }
        case "Bash":
            if let cmd = input["command"]?.value as? String {
                // Truncate long commands
                let trimmed = cmd.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.count > 60 ? String(trimmed.prefix(60)) + "..." : trimmed
            }
        case "Grep":
            if let pattern = input["pattern"]?.value as? String {
                return pattern.count > 40 ? String(pattern.prefix(40)) + "..." : pattern
            }
        case "Glob":
            if let pattern = input["pattern"]?.value as? String {
                return pattern
            }
        case "Task":
            if let prompt = input["prompt"]?.value as? String {
                return prompt.count > 50 ? String(prompt.prefix(50)) + "..." : prompt
            }
        case "WebFetch":
            if let url = input["url"]?.value as? String {
                return url.count > 50 ? String(url.prefix(50)) + "..." : url
            }
        case "WebSearch":
            if let query = input["query"]?.value as? String {
                return query
            }
        default:
            // For other tools, try common keys
            for key in ["file_path", "command", "query", "pattern", "url", "path"] {
                if let val = input[key]?.value as? String {
                    let trimmed = val.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.count > 50 ? String(trimmed.prefix(50)) + "..." : trimmed
                }
            }
        }
        return nil
    }

    /// Format a concise result summary for completed tools
    private static func formatToolResultSummary(toolName: String?, toolUseId: String, session: SessionState) -> String? {
        // Try to get structured result from chatItems
        guard let item = session.chatItems.first(where: { $0.id == toolUseId }),
              case .toolCall(let tool) = item.type else { return nil }

        if let structured = tool.structuredResult {
            switch structured {
            case .edit:
                return "edited"
            case .bash(let r):
                return r.returnCodeInterpretation ?? (r.interrupted ? "interrupted" : "done")
            case .read(let r):
                return "\(r.numLines) lines"
            case .grep(let r):
                return "\(r.numFiles) files"
            case .glob(let r):
                return "\(r.numFiles) files"
            default:
                return nil
            }
        }
        return nil
    }

    /// Extract tool input from AnyCodable dictionary
    private static func extractToolInput(from hookInput: [String: AnyCodable]?) -> [String: String] {
        var input: [String: String] = [:]
        guard let hookInput = hookInput else { return input }

        for (key, value) in hookInput {
            if let str = value.value as? String {
                input[key] = str
            } else if let num = value.value as? Int {
                input[key] = String(num)
            } else if let bool = value.value as? Bool {
                input[key] = bool ? "true" : "false"
            }
        }
        return input
    }
}
