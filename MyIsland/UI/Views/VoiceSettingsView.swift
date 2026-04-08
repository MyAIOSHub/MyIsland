//
//  VoiceSettingsView.swift
//  MyIsland
//
//  Voice input settings panel: toggle, ASR mode, API key, Base URL
//

import SwiftUI

struct VoiceSettingsView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject var voiceCoordinator: VoiceInputCoordinator
    @ObservedObject var processor: ASRPostProcessor

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Header
                headerSection

                // Voice input toggle
                MenuToggleRow(
                    icon: "mic",
                    label: "语音输入 (Fn)",
                    isOn: voiceCoordinator.isEnabled
                ) {
                    voiceCoordinator.isEnabled.toggle()
                }

                // Settings (only when enabled)
                if voiceCoordinator.isEnabled {
                    ASRModeRow()
                    APIKeyRow()
                    BaseURLRow()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    viewModel.contentType = .menu
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(.plain)

            Text("语音设置")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)

            Spacer()
        }
        .padding(.horizontal, 4)
    }
}
