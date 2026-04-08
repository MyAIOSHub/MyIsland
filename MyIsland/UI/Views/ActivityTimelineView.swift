//
//  ActivityTimelineView.swift
//  MyIsland
//
//  Scrollable timeline of recent tool executions for a session
//

import Combine
import SwiftUI

struct ActivityTimelineView: View {
    let toolHistory: [ToolExecution]
    let isProcessing: Bool

    private let claudeOrange = Color(red: 0.85, green: 0.47, blue: 0.34)
    private let spinnerSymbols = ["·", "✢", "✳", "∗", "✻", "✽"]

    /// Reversed history (most recent first), limited to last 20
    private var recentHistory: [ToolExecution] {
        Array(toolHistory.suffix(20).reversed())
    }

    var body: some View {
        if recentHistory.isEmpty && !isProcessing {
            Text("No recent activity")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.3))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    // Show thinking indicator if processing and no active tool
                    if isProcessing && !recentHistory.contains(where: { $0.isActive }) {
                        ThinkingRow()
                    }

                    ForEach(recentHistory) { execution in
                        ToolExecutionRow(execution: execution)
                    }
                }
            }
            .frame(maxHeight: 200)
        }
    }
}

// MARK: - Tool Execution Row

struct ToolExecutionRow: View {
    let execution: ToolExecution

    @State private var spinnerPhase = 0
    private let claudeOrange = Color(red: 0.85, green: 0.47, blue: 0.34)
    private let spinnerSymbols = ["·", "✢", "✳", "∗", "✻", "✽"]
    private let spinnerTimer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Top line: icon + tool name + input summary
            HStack(spacing: 6) {
                // Status icon
                if execution.isActive {
                    Text(spinnerSymbols[spinnerPhase % spinnerSymbols.count])
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(claudeOrange)
                        .frame(width: 12)
                        .onReceive(spinnerTimer) { _ in
                            spinnerPhase = (spinnerPhase + 1) % spinnerSymbols.count
                        }
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(TerminalColors.green.opacity(0.7))
                        .frame(width: 12)
                }

                // Tool name
                Text(MCPToolFormatter.formatToolName(execution.toolName))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(claudeOrange)

                // Input summary
                if let input = execution.toolInput {
                    Text(input)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)
            }

            // Bottom line: result + time
            HStack(spacing: 6) {
                Spacer()
                    .frame(width: 12)

                if let result = execution.result {
                    Text(result)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.35))
                }

                if execution.isActive {
                    Text(execution.elapsed)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.35))
                } else {
                    Text(execution.timeAgo)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.25))
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            execution.isActive
                ? Color.white.opacity(0.04)
                : Color.clear
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.04))
                .frame(height: 0.5)
        }
    }
}

// MARK: - Thinking Row

struct ThinkingRow: View {
    @State private var dotPhase = 0
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    private var dots: String {
        String(repeating: ".", count: (dotPhase % 3) + 1)
    }

    var body: some View {
        HStack(spacing: 6) {
            Text("·")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.4))
                .frame(width: 12)

            Text("Thinking\(dots)")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.03))
        .onReceive(timer) { _ in
            dotPhase += 1
        }
    }
}
