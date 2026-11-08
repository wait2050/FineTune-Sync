import AppKit
import SwiftUI
import Testing
@testable import FineTune

@Suite("Master volume — popup layout")
@MainActor
struct MasterVolumeRenderTests {
    @Test("Total and device controls fit all popup widths in Chinese, light/dark and muted states")
    func render() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("build")
        for width in [470.0, 510, 560] {
            for (name, scheme, appearance) in [("light", ColorScheme.light, NSAppearance.Name.aqua), ("dark", .dark, .darkAqua)] {
                for muted in [false, true] {
                    let content = VStack(spacing: 8) {
                        MasterVolumeRow(volume: 0.25, isMuted: muted, isFocused: false, onVolumeChange: { _ in }, onMuteToggle: {})
                        Divider()
                        DeviceRow(
                            device: AudioDevice(id: 1, uid: "speaker", name: "Mac mini扬声器", icon: NSImage(systemSymbolName: "hifispeaker.fill", accessibilityDescription: nil), supportsAutoEQ: false),
                            isDefault: true, volume: 0.6, isMuted: false,
                            onSetDefault: {}, onVolumeChange: { _ in }, onMuteToggle: {}
                        )
                        DeviceRow(
                            device: AudioDevice(id: 2, uid: "sub", name: "YS-MT21 低音炮", icon: NSImage(systemSymbolName: "hifispeaker.fill", accessibilityDescription: nil), supportsAutoEQ: false),
                            isDefault: false, volume: 0.3, isMuted: false,
                            onSetDefault: {}, onVolumeChange: { _ in }, onMuteToggle: {}
                        )
                    }
                    .padding(12)
                    .frame(width: width)
                    .background(scheme == .light ? Color.white : Color(white: 0.12))
                    .environment(\.colorScheme, scheme)
                    .environment(\.locale, Locale(identifier: "zh-Hans"))
                    let host = NSHostingView(rootView: content)
                    host.appearance = NSAppearance(named: appearance)
                    host.frame = NSRect(x: 0, y: 0, width: width, height: 180)
                    let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: width, height: 180), styleMask: .borderless, backing: .buffered, defer: false)
                    window.appearance = host.appearance
                    window.contentView = host
                    host.layoutSubtreeIfNeeded()
                    #expect(host.fittingSize.width <= width)
                    #expect(host.fittingSize.height <= 180)
                    if width == 510 {
                        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                        host.cacheDisplay(in: host.bounds, to: bitmap)
                        let png = try #require(bitmap.representation(using: .png, properties: [:]))
                        try png.write(to: directory.appendingPathComponent("MasterVolume-\(name)\(muted ? "-muted" : "").png"))
                    }
                    window.contentView = nil
                }
            }
        }
    }
}
