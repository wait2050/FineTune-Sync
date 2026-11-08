import AppKit
import SwiftUI
import Testing
@testable import FineTune

@Suite("Output-device EQ — menu layout")
@MainActor
struct DeviceEQRenderTests {
    @Test("Expanded device EQ fits every popup width in light and dark appearances")
    func renderDeviceEQ() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("build")
        for width in [470.0, 510, 560] {
            for (name, scheme, appearance) in [("light", ColorScheme.light, NSAppearance.Name.aqua), ("dark", .dark, .darkAqua)] {
                let content = VStack(spacing: 0) {
                    DeviceRow(
                        device: AudioDevice(id: 1, uid: "speaker", name: "Mac mini扬声器", icon: NSImage(systemSymbolName: "hifispeaker.fill", accessibilityDescription: nil), supportsAutoEQ: false),
                        isDefault: true, volume: 0.5, isMuted: false,
                        onSetDefault: {}, onVolumeChange: { _ in }, onMuteToggle: {},
                        eqSettings: EQSettings(bandGains: [-6, -4, -2, 0, 0, 0, 1, 2, 1, 0]),
                        isEQExpanded: true, onEQChange: { _ in }
                    )
                    DeviceRow(
                        device: AudioDevice(id: 2, uid: "sub", name: "YS-MT21 低音炮", icon: NSImage(systemSymbolName: "hifispeaker.fill", accessibilityDescription: nil), supportsAutoEQ: false),
                        isDefault: false, volume: 0.4, isMuted: false,
                        onSetDefault: {}, onVolumeChange: { _ in }, onMuteToggle: {},
                        eqSettings: .disabled, onEQChange: { _ in }
                    )
                }
                .padding(12)
                .frame(width: width)
                .background(DesignTokens.Colors.recessedBackground)
                .background(scheme == .light ? Color.white : Color(white: 0.12))
                .environment(\.colorScheme, scheme)
                .environment(\.locale, Locale(identifier: "zh-Hans"))
                let host = NSHostingView(rootView: content)
                host.appearance = NSAppearance(named: appearance)
                host.frame = NSRect(x: 0, y: 0, width: width, height: 340)
                let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: width, height: 340), styleMask: .borderless, backing: .buffered, defer: false)
                window.appearance = host.appearance
                window.contentView = host
                host.layoutSubtreeIfNeeded()
                #expect(host.fittingSize.width <= width)
                #expect(host.fittingSize.height <= 340)
                if width == 510 {
                    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    let png = try #require(bitmap.representation(using: .png, properties: [:]))
                    try png.write(to: directory.appendingPathComponent("DeviceEQUI-\(name).png"))
                }
                window.contentView = nil
            }
        }
    }
}
