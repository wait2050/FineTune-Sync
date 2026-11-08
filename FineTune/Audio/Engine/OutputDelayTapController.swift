import Foundation

/// Main-thread registry. Device UIDs survive reconnects; RT callbacks only read controls.
@MainActor
final class OutputDelayRegistry {
    private let settings: SettingsManager
    private var controls: [String: OutputDelayControl] = [:]

    init(settings: SettingsManager) { self.settings = settings }

    func control(for uid: String) -> OutputDelayControl {
        if let control = controls[uid] { return control }
        let control = OutputDelayControl(milliseconds: settings.outputDelayMilliseconds(for: uid))
        controls[uid] = control
        return control
    }

    func setMilliseconds(_ milliseconds: Double, for uid: String) {
        control(for: uid).setMilliseconds(milliseconds)
        settings.setOutputDelayMilliseconds(milliseconds, for: uid)
    }
}

/// Uses independent renderers when delay compensation or output-device EQ is enabled.
/// Other routes retain the original multi-output aggregate and crossfade behavior.
@MainActor
final class OutputDelayTapController: ProcessTapControlling {
    typealias Factory = @MainActor ([String], String?, OutputDelayControl?) throws -> any ProcessTapControlling
    let app: AudioApp
    private let registry: OutputDelayRegistry
    private let factory: Factory
    private var enabled: Bool
    private var deviceEQSettings: [String: EQSettings]
    private var usesIndependentOutputs = false
    private var active = false
    private var sourceUID: String?
    private var targets: [String]
    private var children: [any ProcessTapControlling] = []
    private var staged: [any ProcessTapControlling] = []
    private var initial = TapInitialState()
    private var pending: Task<Void, Error>?
    private var lifecycle: UInt64 = 0
    private var operationID: UInt64 = 0

    var volume: Float = 1 { didSet { for child in allChildren { child.volume = volume } } }
    var masterGain: Float = 1 { didSet { for child in allChildren { child.masterGain = masterGain } } }
    var isMuted: Bool = false { didSet { for child in allChildren { child.isMuted = isMuted } } }
    var currentDeviceVolume: Float = 1 { didSet { for child in allChildren { child.currentDeviceVolume = currentDeviceVolume } } }
    var isDeviceMuted: Bool = false { didSet { for child in allChildren { child.isDeviceMuted = isDeviceMuted } } }
    private var allChildren: [any ProcessTapControlling] { children + staged }
    var currentDeviceUIDs: [String] { active ? targets : [] }
    var currentDeviceUID: String? { currentDeviceUIDs.first }
    var tapSourceDeviceUID: String? { sourceUID }
    var audioLevel: Float { children.map(\.audioLevel).max() ?? 0 }

    init(app: AudioApp, targetDeviceUIDs: [String], sourceUID: String?, enabled: Bool,
         registry: OutputDelayRegistry, deviceEQSettings: [String: EQSettings] = [:],
         factory: @escaping Factory) {
        precondition(!targetDeviceUIDs.isEmpty)
        self.app = app
        var seen = Set<String>()
        targets = targetDeviceUIDs.filter { seen.insert($0).inserted }
        self.sourceUID = sourceUID
        self.enabled = enabled
        self.deviceEQSettings = deviceEQSettings
        self.registry = registry
        self.factory = factory
    }

    func activate(initial: TapInitialState) throws {
        guard !active else { return }
        self.initial = initial
        usesIndependentOutputs = needsIndependentOutputs(for: targets, enabled: enabled, settings: deviceEQSettings)
        children = try makeChildren(for: targets, sourceUID: sourceUID, enabled: enabled,
                                    split: usesIndependentOutputs, deviceEQSettings: deviceEQSettings, muted: isMuted)
        active = true
    }

    private func needsIndependentOutputs(for uids: [String], enabled: Bool, settings: [String: EQSettings]) -> Bool {
        enabled || uids.contains { settings[$0]?.isEnabled == true }
    }

    private func makeChildren(for uids: [String], sourceUID: String?, enabled: Bool,
                              split: Bool, deviceEQSettings: [String: EQSettings], muted: Bool) throws -> [any ProcessTapControlling] {
        let groups = split ? uids.map { [$0] } : [uids]
        var created: [any ProcessTapControlling] = []
        do {
            for group in groups {
                let child = try factory(group, sourceUID, enabled ? registry.control(for: group[0]) : nil)
                created.append(child) // Include partially-activated controllers in cleanup.
                child.volume = volume
                child.masterGain = masterGain
                child.isMuted = muted
                child.currentDeviceVolume = currentDeviceVolume
                child.isDeviceMuted = isDeviceMuted
                var state = initial
                state.deviceEQSettings = deviceEQSettings[group[0]] ?? .disabled
                try child.activate(initial: state)
            }
            return created
        } catch {
            for child in created { child.invalidate() }
            throw error
        }
    }

    /// All HAL lifecycle operations are serialized. Invalidation also retires the lifecycle
    /// token, so a suspended operation cannot resurrect a removed app after teardown.
    private func serialize(_ body: @escaping @MainActor () async throws -> Void) async throws {
        let previous = pending
        let token = lifecycle
        operationID &+= 1
        let id = operationID
        let task = Task { @MainActor in
            _ = try? await previous?.value
            try Task.checkCancellation()
            guard self.active, self.lifecycle == token else { throw CancellationError() }
            try await body()
        }
        pending = task
        defer { if operationID == id { pending = nil } }
        try await task.value
    }

    func setDelayEnabled(_ newValue: Bool) async throws {
        try await serialize {
            guard self.enabled != newValue else { return }
            try await self.replaceChildren(for: self.targets, sourceUID: self.sourceUID,
                                           enabled: newValue, deviceEQSettings: self.deviceEQSettings)
            self.enabled = newValue
        }
    }

    func setDeviceEQSettings(_ settings: [String: EQSettings]) async throws {
        try await serialize {
            let split = self.needsIndependentOutputs(for: self.targets, enabled: self.enabled, settings: settings)
            if split != self.usesIndependentOutputs {
                try await self.replaceChildren(for: self.targets, sourceUID: self.sourceUID,
                                               enabled: self.enabled, deviceEQSettings: settings)
            } else {
                for child in self.children {
                    let outputSettings = child.currentDeviceUID.flatMap { settings[$0] } ?? .disabled
                    child.updateOutputEQSettings(outputSettings)
                }
            }
            self.deviceEQSettings = settings
        }
    }

    /// Prepare replacements before retiring the old routes so setup failures preserve playback.
    private func replaceChildren(for uids: [String], sourceUID: String?, enabled: Bool,
                                 deviceEQSettings: [String: EQSettings]) async throws {
        let split = needsIndependentOutputs(for: uids, enabled: enabled, settings: deviceEQSettings)
        staged = try makeChildren(for: uids, sourceUID: sourceUID, enabled: enabled, split: split,
                                  deviceEQSettings: deviceEQSettings, muted: true)
        let token = lifecycle
        let old = children
        for child in old { await child.invalidateAsync() }
        guard active, token == lifecycle, !Task.isCancelled else {
            for child in staged { child.invalidate() }
            staged = []
            throw CancellationError()
        }
        children = staged
        staged = []
        usesIndependentOutputs = split
        for child in children { child.isMuted = isMuted }
    }

    func updateDevices(to requestedUIDs: [String], preferredTapSourceDeviceUID: String?, sourceDeviceDead: Bool) async throws {
        precondition(!requestedUIDs.isEmpty)
        var seen = Set<String>()
        let uids = requestedUIDs.filter { seen.insert($0).inserted }
        try await serialize {
            let token = self.lifecycle
            let split = self.needsIndependentOutputs(for: uids, enabled: self.enabled, settings: self.deviceEQSettings)
            if split != self.usesIndependentOutputs {
                try await self.replaceChildren(for: uids, sourceUID: preferredTapSourceDeviceUID,
                                               enabled: self.enabled, deviceEQSettings: self.deviceEQSettings)
            } else if !split {
                try await self.children[0].updateDevices(to: uids, preferredTapSourceDeviceUID: preferredTapSourceDeviceUID, sourceDeviceDead: sourceDeviceDead)
                self.children[0].updateOutputEQSettings(.disabled)
            } else {
                // Keep unchanged outputs (and their delay histories) alive when adding or
                // removing another output. New routes are committed only after all start.
                let additions = uids.filter { !self.targets.contains($0) }
                let previousSource = self.sourceUID
                if previousSource != preferredTapSourceDeviceUID {
                    for child in self.children where uids.contains(child.currentDeviceUID ?? "") {
                        try await child.refreshTapSource(preferredTapSourceDeviceUID)
                        guard self.active, token == self.lifecycle else { throw CancellationError() }
                    }
                }
                self.sourceUID = preferredTapSourceDeviceUID
                let added: [any ProcessTapControlling]
                do {
                    added = try self.makeChildren(for: additions, sourceUID: self.sourceUID, enabled: self.enabled,
                                                  split: true, deviceEQSettings: self.deviceEQSettings, muted: self.isMuted)
                }
                catch { self.sourceUID = previousSource; throw error }
                let retained = self.children.filter { uids.contains($0.currentDeviceUID ?? "") }
                let removed = self.children.filter { !uids.contains($0.currentDeviceUID ?? "") }
                let combined = retained + added
                self.children = uids.compactMap { uid in combined.first { $0.currentDeviceUID == uid } }
                for child in removed { child.invalidate() }
            }
            guard self.active, token == self.lifecycle else { throw CancellationError() }
            self.targets = uids
            self.sourceUID = preferredTapSourceDeviceUID
        }
    }

    func switchDevice(to uid: String, preferredTapSourceDeviceUID: String?, sourceDeviceDead: Bool) async throws {
        try await updateDevices(to: [uid], preferredTapSourceDeviceUID: preferredTapSourceDeviceUID, sourceDeviceDead: sourceDeviceDead)
    }

    func refreshTapSource(_ preferredDeviceUID: String?) async throws {
        try await serialize {
            let token = self.lifecycle
            for child in self.children {
                try await child.refreshTapSource(preferredDeviceUID)
                guard self.active, token == self.lifecycle else { throw CancellationError() }
            }
            self.sourceUID = preferredDeviceUID
        }
    }

    func recreateForOutputRateChange() async throws {
        try await serialize {
            let token = self.lifecycle
            for child in self.children {
                try await child.recreateForOutputRateChange()
                guard self.active, token == self.lifecycle else { throw CancellationError() }
            }
        }
    }

    func invalidate() {
        lifecycle &+= 1
        active = false
        pending?.cancel()
        pending = nil
        for child in allChildren { child.invalidate() }
        children = []
        staged = []
    }

    func invalidateAsync() async {
        lifecycle &+= 1
        active = false
        pending?.cancel()
        pending = nil
        let retired = allChildren
        children = []
        staged = []
        for child in retired { await child.invalidateAsync() }
    }

    func updateEQSettings(_ settings: EQSettings) {
        initial.eqSettings = settings
        for child in allChildren { child.updateEQSettings(settings) }
    }
    func updateAutoEQProfile(_ profile: AutoEQProfile?) {
        initial.autoEQProfile = profile
        for child in allChildren { child.updateAutoEQProfile(profile) }
    }
    func setAutoEQPreampEnabled(_ enabled: Bool) {
        initial.autoEQPreampEnabled = enabled
        for child in allChildren { child.setAutoEQPreampEnabled(enabled) }
    }
    func updateLoudnessCompensation(volume: Float, enabled: Bool) {
        initial.loudnessVolume = volume
        initial.loudnessCompensationEnabled = enabled
        for child in allChildren { child.updateLoudnessCompensation(volume: volume, enabled: enabled) }
    }
    func updateLoudnessEqualization(_ settings: LoudnessEqualizerSettings) {
        initial.loudnessEqualizerSettings = settings
        for child in allChildren { child.updateLoudnessEqualization(settings) }
    }
    func hasRecentAudioCallback(within seconds: Double) -> Bool {
        !children.isEmpty && children.allSatisfy { $0.hasRecentAudioCallback(within: seconds) }
    }
    func isHealthCheckEligible(minActiveSeconds: Double) -> Bool {
        !children.isEmpty && children.allSatisfy { $0.isHealthCheckEligible(minActiveSeconds: minActiveSeconds) }
    }

    isolated deinit { invalidate() }
}
