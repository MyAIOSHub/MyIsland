import SwiftUI

// MARK: - Visual State for Waveform

enum WaveformMode: Equatable {
    case speaking     // Active voice input — dynamic colors & amplitude
    case quiet        // Silent — subtle idle breathing
    case processing   // After speaking — shrink & color shift
}

// MARK: - Enhanced Waveform View

/// Rich, dynamic waveform that changes behavior across 3 modes:
///  1. Speaking    — gradient colors (white→cyan), large amplitude, glow
///  2. Quiet       — gentle breathing pulse, muted colors
///  3. Processing  — dots shrink and fade to gray-blue with pulse
///
/// Design: stateless for animation phase (uses `Date()` so no timer is needed
/// and no state is lost when the DynamicNotch framework resets view identity).
struct WaveformView: View {
    let levels: [CGFloat]
    let mode: WaveformMode

    var dotCount: Int = 5
    var minDotSize: CGFloat = 3
    var maxDotSize: CGFloat = 16
    var spacing: CGFloat = 4

    @State private var smoothed: [CGFloat] = []
    @State private var showScale: CGFloat = 0

    // Smoothing rates
    private let riseRate: CGFloat = 0.55
    private let fallRate: CGFloat = 0.12

    /// Time-based phase for breathing / processing animations.
    /// No timer or state needed — recomputed each render (~30fps from audio updates).
    private var phase: CGFloat {
        CGFloat(Date().timeIntervalSinceReferenceDate * 3.0)
    }

    init(levels: [CGFloat],
         mode: WaveformMode = .speaking,
         barCount: Int = 5,
         barWidth: CGFloat = 3,
         spacing: CGFloat = 4,
         maxHeight: CGFloat = 16,
         minHeight: CGFloat = 3) {
        self.levels = levels
        self.mode = mode
        self.dotCount = barCount
        self.minDotSize = minHeight
        self.spacing = spacing
        self.maxDotSize = maxHeight
    }

    // MARK: - Computed

    private var averageLevel: CGFloat {
        guard !levels.isEmpty else { return 0 }
        return levels.reduce(0, +) / CGFloat(levels.count)
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<dotCount, id: \.self) { i in
                dotView(index: i)
            }
        }
        .scaleEffect(showScale)
        .onAppear {
            // Initialize smoothed
            if smoothed.count != dotCount {
                smoothed = Array(repeating: 0, count: dotCount)
            }
            // Appear animation
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                showScale = 1.0
            }
        }
        .onChange(of: levels) { _ in
            updateSmoothing()
        }
    }

    // MARK: - Individual Dot

    @ViewBuilder
    private func dotView(index i: Int) -> some View {
        let level = smoothed.indices.contains(i) ? smoothed[i] : 0
        let size = dotSize(index: i, level: level)
        let color = dotColor(index: i, level: level)

        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(
                color: glowColor(index: i, level: level),
                radius: glowRadius(level: level),
                x: 0, y: 0
            )
            .animation(.easeOut(duration: 0.1), value: size)
    }

    // MARK: - Size

    private func dotSize(index: Int, level: CGFloat) -> CGFloat {
        switch mode {
        case .speaking:
            let centerWeight = centerBias(index: index)
            let effectiveLevel = level * (0.6 + 0.4 * centerWeight)
            return minDotSize + (maxDotSize - minDotSize) * effectiveLevel

        case .quiet:
            let wave = sin(phase * 0.8 + CGFloat(index) * 0.8) * 0.3
            let baseSize = minDotSize + 2
            return baseSize + wave * 2

        case .processing:
            let pulse = sin(phase * 1.2 + CGFloat(index) * 0.6) * 0.2
            let baseSize = minDotSize + 1.5
            return baseSize + pulse * 1.5
        }
    }

    // MARK: - Color

    private func dotColor(index: Int, level: CGFloat) -> Color {
        switch mode {
        case .speaking:
            let intensity = min(1.0, level * 1.3)
            if intensity < 0.3 {
                return .white.opacity(0.85 + Double(intensity) * 0.15)
            } else if intensity < 0.6 {
                let t = (intensity - 0.3) / 0.3
                return Color(
                    red: 1.0 - Double(t) * 0.15,
                    green: 1.0 - Double(t) * 0.02,
                    blue: 1.0
                )
            } else {
                let t = (intensity - 0.6) / 0.4
                return Color(
                    red: 0.85 - Double(t) * 0.2,
                    green: 0.98 - Double(t) * 0.08,
                    blue: 1.0
                )
            }

        case .quiet:
            let alpha = 0.5 + sin(phase * 0.8 + CGFloat(index) * 0.6) * 0.15
            return .white.opacity(Double(alpha))

        case .processing:
            let alpha = 0.45 + sin(phase * 1.2 + CGFloat(index) * 0.5) * 0.15
            return Color(red: 0.7, green: 0.75, blue: 0.85).opacity(Double(alpha))
        }
    }

    // MARK: - Glow

    private func glowColor(index: Int, level: CGFloat) -> Color {
        switch mode {
        case .speaking:
            let intensity = min(1.0, level * 1.2)
            if intensity > 0.4 {
                return Color.cyan.opacity(Double(intensity - 0.4) * 0.6)
            }
            return .clear
        case .processing:
            return Color.blue.opacity(0.1)
        default:
            return .clear
        }
    }

    private func glowRadius(level: CGFloat) -> CGFloat {
        switch mode {
        case .speaking:
            return level > 0.4 ? level * 6 : 0
        case .processing:
            return 2
        default:
            return 0
        }
    }

    // MARK: - Center Bias

    private func centerBias(index: Int) -> CGFloat {
        let center = CGFloat(dotCount - 1) / 2.0
        guard center > 0 else { return 1.0 }
        let distance = abs(CGFloat(index) - center) / center
        return 1.0 - distance * 0.4
    }

    // MARK: - Smoothing

    private func updateSmoothing() {
        guard mode == .speaking || mode == .quiet else { return }

        var result = Array(repeating: CGFloat(0), count: dotCount)
        for i in 0..<dotCount {
            let raw = i < levels.count ? levels[i] : averageLevel
            let prev = smoothed.indices.contains(i) ? smoothed[i] : 0

            if raw > prev {
                result[i] = prev + (raw - prev) * riseRate
            } else {
                result[i] = prev + (raw - prev) * fallRate
            }
        }
        smoothed = result
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }
}
