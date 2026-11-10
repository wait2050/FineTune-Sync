import Testing
import AppKit
@testable import FineTune

@Suite("MonoSplit logical output") @MainActor
struct MonoSplitRoutingTests {
    private let app = AudioApp(id: 91824, processObjectIDs: [], name: "Bridge test", icon: NSImage(), bundleID: "test.bridge")

    @Test("MonoSplit and physical outputs use independent renderers without enabling delay")
    func mixedOutputs() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = SettingsManager(directory: directory)
        var children: [RecordingProcessTapController] = []
        let wrapper = OutputDelayTapController(app: app, targetDeviceUIDs: [MonoSplitEndpoint.uid, "usb"], sourceUID: nil,
                                              enabled: false, registry: OutputDelayRegistry(settings: settings),
                                              outputGain: { $0 == MonoSplitEndpoint.uid ? 0.25 : 1 }) { uids, _, _ in
            let child = RecordingProcessTapController(app: app, deviceUIDs: uids)
            children.append(child)
            return child
        }
        try wrapper.activate(initial: TapInitialState())
        #expect(children.map(\.currentDeviceUIDs) == [[MonoSplitEndpoint.uid], ["usb"]])
        wrapper.volume = 0.4
        #expect(abs(children[0].volume - 0.1) < 0.0001)
        #expect(children[1].volume == 0.4)
        wrapper.masterGain = 0
        #expect(children.allSatisfy { $0.masterGain == 0 })
        wrapper.isMuted = true
        #expect(children.allSatisfy { $0.isMuted })
        wrapper.invalidate()
    }

    @Test("Switching between hardware and MonoSplit replaces the renderer and retains controls")
    func switching() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = SettingsManager(directory: directory)
        var children: [RecordingProcessTapController] = []
        let wrapper = OutputDelayTapController(app: app, targetDeviceUIDs: ["usb"], sourceUID: nil,
                                              enabled: false, registry: OutputDelayRegistry(settings: settings)) { uids, _, _ in
            let child = RecordingProcessTapController(app: app, deviceUIDs: uids)
            children.append(child)
            return child
        }
        wrapper.volume = 0.2
        wrapper.masterGain = 0.3
        try wrapper.activate(initial: TapInitialState())
        try await wrapper.updateDevices(to: [MonoSplitEndpoint.uid], preferredTapSourceDeviceUID: nil, sourceDeviceDead: false)
        #expect(wrapper.currentDeviceUIDs == [MonoSplitEndpoint.uid])
        #expect(children.count == 2 && children[0].events.contains(.invalidate))
        #expect(children[1].volume == 0.2 && children[1].masterGain == 0.3)
        try await wrapper.updateDevices(to: ["usb"], preferredTapSourceDeviceUID: nil, sourceDeviceDead: false)
        #expect(wrapper.currentDeviceUIDs == ["usb"])
        #expect(children.count == 3 && children[1].events.contains(.invalidate))
        wrapper.invalidate()
    }

    @Test("Unavailable MonoSplit preserves the previously working output")
    func failedConnection() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = SettingsManager(directory: directory)
        let physical = RecordingProcessTapController(app: app, deviceUIDs: ["usb"])
        let wrapper = OutputDelayTapController(app: app, targetDeviceUIDs: ["usb"], sourceUID: nil,
                                              enabled: false, registry: OutputDelayRegistry(settings: settings)) { uids, _, _ in
            if uids.contains(MonoSplitEndpoint.uid) { throw CocoaError(.fileReadNoSuchFile) }
            return physical
        }
        try wrapper.activate(initial: TapInitialState())
        do {
            try await wrapper.updateDevices(to: [MonoSplitEndpoint.uid], preferredTapSourceDeviceUID: nil, sourceDeviceDead: false)
            Issue.record("Expected a failed connection")
        } catch {
            #expect(wrapper.currentDeviceUIDs == ["usb"])
            #expect(!physical.events.contains(.invalidate))
        }
        wrapper.invalidate()
    }
}
