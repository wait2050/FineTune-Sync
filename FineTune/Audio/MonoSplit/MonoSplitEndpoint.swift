import AppKit
import AudioToolbox

/// App-local output, deliberately outside the HAL object namespace.
nonisolated enum MonoSplitEndpoint {
    static let uid = "com.monosplit.bridge.output.v1"
    static let deviceID: AudioDeviceID = 0xFFFF_FF01
    static let directory = ProcessInfo.processInfo.environment["MONOSPLIT_BRIDGE_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MonoSplitBridge", isDirectory: true)

    struct Session: Decodable, Equatable {
        let version: Int
        let path: String
        let clockUID: String
        let sampleRate: Double
        let pid: Int32
        let updatedAt: Double
        var identity: String { path }
    }

    static func readSession() -> Session? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("endpoint.json")),
              let session = try? JSONDecoder().decode(Session.self, from: data),
              session.version == 1, session.pid > 0, kill(session.pid, 0) == 0,
              session.sampleRate.isFinite, (8000...192000).contains(session.sampleRate),
              !session.clockUID.isEmpty,
              abs(Date().timeIntervalSince1970 - session.updatedAt) < 4,
              URL(fileURLWithPath: session.path).deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL,
              FileManager.default.fileExists(atPath: session.path) else { return nil }
        return session
    }

    @MainActor static var device: AudioDevice {
        AudioDevice(id: deviceID, uid: uid, name: "MonoSplit",
                    icon: NSImage(systemSymbolName: "waveform.path", accessibilityDescription: "MonoSplit"),
                    supportsAutoEQ: false)
    }
    @MainActor static func openTuning() {
        guard let session = readSession() else { return }
        NSRunningApplication(processIdentifier: session.pid)?.activate(options: [])
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.monosplit.showTuning"), object: nil, userInfo: nil, deliverImmediately: true)
    }
}

/// The mapping and track are created/retired on the control thread. The callback
/// only copies into a lock-free ring; no file I/O occurs on the audio thread.
final class MonoSplitPCMSender: @unchecked Sendable {
    private let pointer: OpaquePointer
    let sampleRate: Double
    init(session: MonoSplitEndpoint.Session) throws {
        guard let pointer = mspcm_open_writer(session.path, session.sampleRate) else {
            throw NSError(domain: "MonoSplit", code: 1, userInfo: [NSLocalizedDescriptionKey: L10n.string("The MonoSplit audio bridge is unavailable. Enable FineTune input in MonoSplit and start processing.")])
        }
        self.pointer = pointer
        sampleRate = session.sampleRate
    }
    func consume(_ audio: UnsafeMutablePointer<AudioBufferList>, left: Int, right: Int) {
        let buffers = UnsafeMutableAudioBufferListPointer(audio)
        let count = buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
        if count > 0 { _ = mspcm_write(pointer, audio, Int32(min(left, count - 1)), Int32(min(right, count - 1))) }
        for buffer in UnsafeMutableAudioBufferListPointer(audio) {
            if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
        }
    }
    deinit { mspcm_close(pointer) }
}
