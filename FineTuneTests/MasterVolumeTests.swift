import AppKit
import AudioToolbox
import Foundation
import Testing
@testable import FineTune

@Suite("Master volume — persistence, routing and media keys")
@MainActor
struct MasterVolumeTests {
    private func settings() -> SettingsManager {
        SettingsManager(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    @Test("Old settings retain their levels at unity; master survives restart and reset")
    func persistence() throws {
        let old = try JSONDecoder().decode(SettingsManager.Settings.self, from: Data(#"{"appVolumes":{"music":0.4}}"#.utf8))
        #expect(old.masterVolume == 1)
        #expect(!old.masterMuted)
        #expect(old.appVolumes["music"] == 0.4)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let manager = SettingsManager(directory: directory)
        manager.setMasterVolume(0.36, muted: true)
        manager.flushSync()
        let restored = SettingsManager(directory: directory)
        #expect(restored.masterVolume == 0.36)
        #expect(restored.masterMuted)
        restored.resetAllSettings()
        #expect(restored.masterVolume == 1)
        #expect(!restored.masterMuted)
        for (value, expected) in [(Float(-3), Float(0)), (3, 1)] {
            let data = Data("{\"masterVolume\":\(value)}".utf8)
            let decoded = try JSONDecoder().decode(SettingsManager.Settings.self, from: data)
            #expect(decoded.masterVolume == expected)
        }
    }

    @Test("Every app inherits total volume while app gain, boost, mute and device trims remain independent")
    func independentAppAndDeviceLevels() throws {
        let fix = makeEngine()
        let music = app(1001, "music")
        let video = app(1002, "video")
        fix.engine.setDevice(for: music, deviceUID: "speaker")
        fix.engine.setVolume(for: music, to: 0.4)
        fix.engine.setBoost(for: music, to: .x2)
        fix.engine.setMute(for: music, to: true)
        let musicTap = try #require(fix.taps.values[music.id])

        fix.engine.setMasterVolume(0.25)
        #expect(musicTap.masterGain == 0.25)
        #expect(musicTap.volume == 0.8)
        #expect(musicTap.isMuted)
        #expect(fix.engine.getVolume(for: music) == 0.4)
        #expect(fix.engine.getBoost(for: music) == .x2)
        #expect(fix.deviceVolume.setVolumeCalls.isEmpty)
        #expect(fix.deviceVolume.setMuteCalls.isEmpty)

        // A new app on another device gets the same total before activation.
        fix.engine.setDevice(for: video, deviceUID: "usb")
        let videoTap = try #require(fix.taps.values[video.id])
        #expect(videoTap.masterGain == 0.25)
        #expect(videoTap.masterGainAtActivation == 0.25)
        fix.engine.toggleMasterMute()
        #expect(musicTap.masterGain == 0)
        #expect(videoTap.masterGain == 0)
        #expect(!videoTap.isMuted)
        fix.engine.toggleMasterMute()
        #expect(musicTap.masterGain == 0.25)
        #expect(videoTap.masterGain == 0.25)
        #expect(musicTap.isMuted)

        fix.engine.setMasterVolume(.nan)
        #expect(fix.engine.masterVolume == 0.25)
        fix.engine.setMasterVolume(0)
        fix.engine.toggleMasterMute()
        #expect(fix.engine.masterVolume == 0.25)
        #expect(!fix.engine.isMasterMuted)
    }

    @Test("Aggregate and independent delay/EQ outputs retain total through additions and renderer replacement")
    func multiOutputLifecycle() async throws {
        for independent in [false, true] {
            var children: [RecordingProcessTapController] = []
            let wrapper = OutputDelayTapController(
                app: app(1003, "multi"), targetDeviceUIDs: ["speaker", "usb"], sourceUID: nil,
                enabled: independent, registry: OutputDelayRegistry(settings: settings())
            ) { appUIDs, _, _ in
                let child = RecordingProcessTapController(app: app(1003, "multi"), deviceUIDs: appUIDs)
                children.append(child)
                return child
            }
            wrapper.masterGain = 0.16
            try wrapper.activate(initial: TapInitialState())
            #expect(children.count == (independent ? 2 : 1))
            #expect(children.allSatisfy { $0.masterGainAtActivation == 0.16 })
            wrapper.masterGain = 0
            #expect(children.allSatisfy { $0.masterGain == 0 })
            try await wrapper.updateDevices(to: ["speaker", "usb", "hdmi"], preferredTapSourceDeviceUID: nil)
            #expect(children.allSatisfy { $0.masterGain == 0 })
            wrapper.masterGain = 0.49
            // Force an aggregate/independent transition while already playing.
            try await wrapper.setDelayEnabled(!independent)
            #expect(children.last?.masterGainAtActivation == 0.49)
            wrapper.invalidate()
        }
    }

    @Test("Media keys change only total and its HUD, including without a default output")
    func mediaKeys() {
        let fix = makeEngine()
        fix.engine.setMasterVolume(0.25)
        let hud = MasterHUD()
        let popup = PopupVisibilityService()
        let monitor = MediaKeyMonitor(
            decoder: StubMediaKeyDecoder(), audioEngine: fix.engine, settingsManager: fix.settings,
            accessibility: MockAccessibilityTrustProviding(isTrusted: true), hudController: hud,
            popupVisibility: popup, mediaKeyStatus: MediaKeyStatus()
        )
        monitor.handle(.volumeUp(isRepeat: false))
        let expected = 0.5 + fix.settings.appSettings.volumeHotkeyStep.sliderDelta
        #expect(abs(fix.engine.masterVolume - VolumeMapping.sliderToGain(expected)) < 0.000001)
        #expect(abs((hud.fraction ?? 0) - expected) < 0.000001)
        #expect(hud.title == L10n.string("Master Volume"))
        let saved = fix.engine.masterVolume
        monitor.handle(.muteToggle)
        #expect(fix.engine.isMasterMuted)
        #expect(hud.muted == true)
        monitor.handle(.muteToggle)
        #expect(!fix.engine.isMasterMuted)
        #expect(fix.engine.masterVolume == saved)
        #expect(fix.deviceVolume.setVolumeCalls.isEmpty)
        #expect(fix.deviceVolume.setMuteCalls.isEmpty)
        fix.engine.setMasterVolume(0)
        monitor.handle(.muteToggle)
        #expect(!fix.engine.isMasterMuted)
        #expect(fix.engine.masterVolume == 0.25)
        #expect(hud.fraction == 0.5)
        popup.isVisible = true
        let count = hud.count
        monitor.handle(.volumeDown(isRepeat: true))
        #expect(hud.count == count)
        #expect(fix.engine.masterVolume < saved)
    }

    private func app(_ pid: pid_t, _ name: String) -> AudioApp {
        AudioApp(id: pid, processObjectIDs: [], name: name, icon: NSImage(), bundleID: "test.master.\(name)")
    }

    private func makeEngine() -> (engine: AudioEngine, settings: SettingsManager, deviceVolume: MockDeviceVolumeProviding, taps: TapStore) {
        let manager = settings()
        let devices = MockAudioDeviceMonitor()
        devices.addOutputDevice(AudioDevice(id: 998, uid: "speaker", name: "Speaker", icon: nil, supportsAutoEQ: false))
        devices.addOutputDevice(AudioDevice(id: 999, uid: "usb", name: "USB", icon: nil, supportsAutoEQ: false))
        let volume = MockDeviceVolumeProviding(deviceMonitor: devices)
        volume.volumes = [998: 0.7, 999: 0.3]
        let permission = AudioRecordingPermission()
        permission.status = .authorized
        let taps = TapStore()
        let engine = AudioEngine(
            permission: permission, settingsManager: manager, autoEQProfileManager: AutoEQProfileManager(),
            deviceProvider: devices, processMonitor: StubProcessMonitor(), deviceVolumeMonitor: volume,
            tapFactory: { app, uids, _ in
                let tap = RecordingProcessTapController(app: app, deviceUIDs: uids)
                taps.values[app.id] = tap
                return tap
            }, startMonitorsAutomatically: false
        )
        return (engine, manager, volume, taps)
    }

    @MainActor private final class TapStore {
        var values: [pid_t: RecordingProcessTapController] = [:]
    }
    @MainActor private final class MasterHUD: MediaKeyHUDPresenting {
        var fraction: Double?
        var muted: Bool?
        var title: String?
        var count = 0
        func show(sliderFraction: Double, mute: Bool, deviceName: String) {
            fraction = sliderFraction
            muted = mute
            title = deviceName
            count += 1
        }
        func swallowObserved() {}
    }
}
