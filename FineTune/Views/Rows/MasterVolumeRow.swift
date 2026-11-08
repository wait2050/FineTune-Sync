import SwiftUI

/// One shared control above device trims. Percentage uses the same perceptual
/// curve as app/software volume and the media-key HUD.
struct MasterVolumeRow: View {
    let volume: Float
    let isMuted: Bool
    var isFocused: Bool = false
    let onVolumeChange: (Float) -> Void
    let onMuteToggle: () -> Void

    private var sliderValue: Double { VolumeMapping.gainToSlider(volume) }
    private var sliderBinding: Binding<Double> {
        Binding(get: { sliderValue }, set: { onVolumeChange(VolumeMapping.sliderToGain($0)) })
    }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.accentPrimary)
                .frame(width: DesignTokens.Dimensions.minTouchTarget)

            VStack(alignment: .leading, spacing: 2) {
                Text("Master Volume")
                    .font(DesignTokens.Typography.rowName)
                Text("All apps managed by FineTune")
                    .font(.system(size: 9))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            MuteButton(isMuted: isMuted || volume == 0, levelFraction: sliderValue, action: onMuteToggle)
                .accessibilityLabel(isMuted || volume == 0 ? Text("Unmute master volume") : Text("Mute master volume"))

            LiquidGlassSlider(value: sliderBinding)
            .frame(width: DesignTokens.Dimensions.sliderWidth)
            .opacity(isMuted || volume == 0 ? 0.5 : 1)
            .scrollWheelStep(sliderBinding, in: 0.0...1.0)
            .accessibilityLabel("Master Volume")

            EditablePercentage(
                percentage: Binding(
                    get: { Int((sliderValue * 100).rounded()) },
                    set: { onVolumeChange(VolumeMapping.sliderToGain(Double($0) / 100)) }
                ),
                range: 0...100,
                isRowFocused: isFocused
            )
        }
        .hoverableRow(isFocused: isFocused)
        .help("Adjust all FineTune playback while keeping app and device levels unchanged")
    }
}
