import AppKit
import Foundation
import Testing
@testable import FineTune

@Suite("Output-device EQ — persistence and independent routes")
@MainActor
struct DeviceEQTests {
    private let app = AudioApp(id: 9981, processObjectIDs: [], name: "Music", icon: NSImage(), bundleID: "test.device-eq")
    private let bass = EQSettings(bandGains: [0, -6, -3, 0, 0, 0, 0, 0, 0, 0])
    private let treble = EQSettings(bandGains: [0, 0, 0, 0, 0, 0, 2, 3, 4, 3])

    private func makeSettings() -> SettingsManager {
        SettingsManager(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    @Test("Existing settings start with device EQ bypassed and retain app EQ and delays")
    func migration() throws {
        let data = Data(#"{"version":13,"appEQSettings":{"music":{"bandGains":[0,0,0,0,0,0,0,2,3,4],"isEnabled":true}},"outputDelayEnabled":true,"outputDelaysMilliseconds":{"speaker":220}}"#.utf8)
        let restored = try JSONDecoder().decode(SettingsManager.Settings.self, from: data)
        #expect(restored.deviceEQSettings.isEmpty)
        #expect(restored.appEQSettings["music"]?.bandGains[9] == 4)
        #expect(restored.outputDelaysMilliseconds["speaker"] == 220)
        #expect(restored.outputDelayEnabled)
    }

    @Test("Each device remembers its curve and bypass state after restart; reset clears them")
    func persistence() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let settings = SettingsManager(directory: directory)
        settings.setEQSettings(treble, for: "music")
        settings.setDeviceEQSettings(bass, for: "sub")
        var bypassed = treble
        bypassed.isEnabled = false
        settings.setDeviceEQSettings(bypassed, for: "speaker")
        settings.flushSync()
        let restored = SettingsManager(directory: directory)
        #expect(restored.getDeviceEQSettings(for: "sub") == bass)
        #expect(restored.getDeviceEQSettings(for: "speaker") == bypassed)
        #expect(restored.getDeviceEQSettings(for: "new-output") == .disabled)
        #expect(restored.getEQSettings(for: "music") == treble)
        restored.resetAllSettings()
        #expect(restored.deviceEQSettings.isEmpty)
    }

    @Test("Device EQ splits outputs while delay compensation is off and preserves app EQ")
    func independentWithoutDelay() async throws {
        let settings = makeSettings()
        var created: [RecordingProcessTapController] = []
        var controls: [OutputDelayControl?] = []
        let wrapper = OutputDelayTapController(
            app: app, targetDeviceUIDs: ["speaker", "sub"], sourceUID: nil,
            enabled: false, registry: OutputDelayRegistry(settings: settings),
            deviceEQSettings: ["speaker": treble, "sub": bass]
        ) { uids, _, control in
            let child = RecordingProcessTapController(app: app, deviceUIDs: uids)
            created.append(child)
            controls.append(control)
            return child
        }
        var initial = TapInitialState()
        initial.eqSettings = treble
        try wrapper.activate(initial: initial)
        #expect(created.map(\.currentDeviceUIDs) == [["speaker"], ["sub"]])
        #expect(controls.allSatisfy { $0 == nil })
        #expect(created[0].outputEQSettings == treble)
        #expect(created[1].outputEQSettings == bass)
        if case .activate(let snapshot) = created[1].events.first {
            #expect(snapshot.eqSettings == treble)
            #expect(snapshot.deviceEQSettings == bass)
        } else { Issue.record("Missing initial EQ state") }
        try await wrapper.setDeviceEQSettings(["speaker": bass, "sub": bass])
        #expect(created.count == 2)
        #expect(created[0].outputEQSettings == bass)
        #expect(created[1].outputEQSettings == bass)
        try await wrapper.updateDevices(to: ["speaker", "sub", "usb", "hdmi"], preferredTapSourceDeviceUID: nil)
        #expect(created.count == 4)
        #expect(created[2].currentDeviceUIDs == ["usb"])
        #expect(created[3].currentDeviceUIDs == ["hdmi"])
        #expect(!created[0].events.contains(.invalidate))
        wrapper.invalidate()
    }

    @Test("Enabling and bypassing EQ rebuilds aggregates safely; reconnect restores the saved device curve")
    func topologyAndReconnect() async throws {
        let settings = makeSettings()
        var created: [RecordingProcessTapController] = []
        let wrapper = OutputDelayTapController(
            app: app, targetDeviceUIDs: ["speaker", "sub"], sourceUID: nil,
            enabled: false, registry: OutputDelayRegistry(settings: settings)
        ) { uids, _, _ in
            let child = RecordingProcessTapController(app: app, deviceUIDs: uids)
            created.append(child)
            return child
        }
        try wrapper.activate()
        #expect(created.count == 1)
        try await wrapper.setDeviceEQSettings(["sub": bass])
        #expect(created.count == 3)
        #expect(created[0].events.contains(.invalidate))
        #expect(created[2].outputEQSettings == bass)
        try await wrapper.updateDevices(to: ["speaker"], preferredTapSourceDeviceUID: nil)
        try await wrapper.updateDevices(to: ["speaker", "sub"], preferredTapSourceDeviceUID: nil)
        #expect(created.last?.outputEQSettings == bass)
        var disabled = bass
        disabled.isEnabled = false
        try await wrapper.setDeviceEQSettings(["sub": disabled])
        #expect(created.last?.currentDeviceUIDs == ["speaker", "sub"])
        #expect(created.last?.outputEQSettings.isEnabled == false)
        wrapper.invalidate()
    }

    @Test("Editing EQ with live delay compensation retains existing renderers and delay values")
    func preservesDelays() async throws {
        let settings = makeSettings()
        settings.setOutputDelayMilliseconds(220, for: "speaker")
        let registry = OutputDelayRegistry(settings: settings)
        var created: [RecordingProcessTapController] = []
        let wrapper = OutputDelayTapController(
            app: app, targetDeviceUIDs: ["speaker", "sub"], sourceUID: nil,
            enabled: true, registry: registry
        ) { uids, _, _ in
            let child = RecordingProcessTapController(app: app, deviceUIDs: uids)
            created.append(child)
            return child
        }
        try wrapper.activate()
        try await wrapper.setDeviceEQSettings(["sub": bass])
        #expect(created.count == 2)
        #expect(created[0].outputEQSettings == .disabled)
        #expect(created[1].outputEQSettings == bass)
        #expect(registry.control(for: "speaker").milliseconds == 220)
        try await wrapper.setDelayEnabled(false)
        #expect(created.suffix(2).map(\.currentDeviceUIDs) == [["speaker"], ["sub"]])
        #expect(created.last?.outputEQSettings == bass)
        wrapper.invalidate()
    }

    @Test("Failed EQ activation preserves the original route and permits retry")
    func failedActivation() async throws {
        enum Failure: Error { case unavailable }
        var fail = true
        var created: [RecordingProcessTapController] = []
        let wrapper = OutputDelayTapController(
            app: app, targetDeviceUIDs: ["speaker", "sub"], sourceUID: nil,
            enabled: false, registry: OutputDelayRegistry(settings: makeSettings())
        ) { uids, _, _ in
            if fail && uids == ["sub"] { throw Failure.unavailable }
            let child = RecordingProcessTapController(app: app, deviceUIDs: uids)
            created.append(child)
            return child
        }
        try wrapper.activate()
        await #expect(throws: Failure.self) { try await wrapper.setDeviceEQSettings(["sub": bass]) }
        #expect(!created[0].events.contains(.invalidate))
        #expect(created[1].events.contains(.invalidate))
        fail = false
        try await wrapper.setDeviceEQSettings(["sub": bass])
        #expect(created.last?.outputEQSettings == bass)
        wrapper.invalidate()
    }

    @Test("Rapid edits across devices are applied together through AudioEngine and survive reset")
    func engineUpdates() async throws {
        let settings = makeSettings()
        let devices = MockAudioDeviceMonitor()
        let speaker = AudioDevice(id: 99, uid: "speaker", name: "Speaker", icon: nil, supportsAutoEQ: false)
        devices.addOutputDevice(speaker)
        let permission = AudioRecordingPermission()
        permission.status = .authorized
        let registry = OutputDelayRegistry(settings: settings)
        var created: [RecordingProcessTapController] = []
        var fail = false
        let engine = AudioEngine(
            permission: permission, settingsManager: settings, autoEQProfileManager: AutoEQProfileManager(),
            deviceProvider: devices, processMonitor: StubProcessMonitor(),
            deviceVolumeMonitor: MockDeviceVolumeProviding(deviceMonitor: devices),
            tapFactory: { app, uids, source in
                OutputDelayTapController(app: app, targetDeviceUIDs: uids, sourceUID: source,
                                         enabled: settings.outputDelayEnabled, registry: registry,
                                         deviceEQSettings: settings.deviceEQSettings) { targets, _, _ in
                    if fail { throw NSError(domain: "DeviceEQTest", code: 1) }
                    let child = RecordingProcessTapController(app: app, deviceUIDs: targets)
                    created.append(child)
                    return child
                }
            }, startMonitorsAutomatically: false
        )
        engine.setDevice(for: app, deviceUID: speaker.uid)
        for gain in 0..<10 {
            engine.setDeviceEQSettings(EQSettings(bandGains: [Float(gain)]), for: "speaker")
        }
        engine.setDeviceEQSettings(bass, for: "sub")
        await engine.deviceEQUpdateTask?.value
        #expect(engine.getDeviceEQSettings(for: "speaker").bandGains[0] == 9)
        #expect(engine.getDeviceEQSettings(for: "sub") == bass)
        #expect(created.last?.outputEQSettings.bandGains[0] == 9)
        #expect(engine.deviceEQError == nil)
        engine.handleSettingsReset()
        await engine.deviceEQUpdateTask?.value
        #expect(created.last?.outputEQSettings == .disabled)
        #expect(settings.deviceEQSettings.isEmpty)
        let original = try #require(created.last)
        fail = true
        engine.setDeviceEQSettings(treble, for: "speaker")
        await engine.deviceEQUpdateTask?.value
        #expect(engine.deviceEQError != nil)
        #expect(settings.deviceEQSettings.isEmpty)
        #expect(!original.events.contains(.invalidate))
        fail = false
        engine.setDeviceEQSettings(treble, for: "speaker")
        await engine.deviceEQUpdateTask?.value
        #expect(created.last?.outputEQSettings == treble)
        #expect(engine.deviceEQError == nil)
        engine.shutdown()
    }
}
