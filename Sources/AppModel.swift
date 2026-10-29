import AppKit
import AVFoundation
import CoreAudio
import ServiceManagement

struct EQSettings: Codable, Equatable {
    static let frequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

    // Defaults: bass-forward EQ curve, Small Room reverb at 50%.
    var enabled = true
    var eqEnabled = true
    var preamp: Float = 0
    var gains: [Float] = [12.4, 7.6, 5.0, 3.1, 2.5, 0, 0, 0, 0, 0]
    var reverbEnabled = true
    var reverbPreset = AVAudioUnitReverbPreset.smallRoom.rawValue
    var reverbMix: Float = 50
    var limiterEnabled = true
}

@MainActor
final class AppModel: ObservableObject {
    @Published var settings: EQSettings {
        didSet {
            guard settings != oldValue else { return }
            save()
            if settings.enabled != oldValue.enabled {
                settings.enabled ? start() : stop()
            } else {
                pipeline.apply(settings)
            }
        }
    }
    @Published private(set) var status = "Off"
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled {
        didSet {
            guard launchAtLogin != oldValue else { return }
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                status = "Launch at login: \(error.localizedDescription)"
            }
        }
    }

    @Published var visualsEnabled = false {
        didSet {
            guard visualsEnabled != oldValue else { return }
            if visualsEnabled {
                visuals.show(effect: visualEffect, analyzer: analyzer)
            } else {
                visuals.close()
            }
        }
    }
    @Published var visualEffect: VisualEffectKind {
        didSet {
            UserDefaults.standard.set(visualEffect.rawValue, forKey: Self.visualEffectKey)
            visuals.setEffect(visualEffect)
        }
    }

    private static let defaultsKey = "settings"
    private static let visualEffectKey = "visualEffect"
    private static let loginItemPathKey = "loginItemPath"
    private let pipeline = AudioPipeline()
    private let visuals = VisualsWindowController()
    private lazy var analyzer = AudioAnalyzer(ring: pipeline.samples) { [pipeline] in pipeline.sampleRate }
    private var restartWork: DispatchWorkItem?

    init() {
        visualEffect = UserDefaults.standard.string(forKey: Self.visualEffectKey)
            .flatMap(VisualEffectKind.init(rawValue:)) ?? .matrixRain
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode(EQSettings.self, from: data) {
            settings = saved
        } else {
            settings = EQSettings()
        }
        pipeline.onConfigurationChange = { [weak self] in
            MainActor.assumeIsolated { self?.scheduleRestart() }
        }
        visuals.onClose = { [weak self] in self?.visualsEnabled = false }
        observeDefaultOutput()
        refreshLoginItemLocation()
        if settings.enabled { start() }
    }

    /// The login item records the app's path; re-register when the app has moved (e.g. after the rename).
    private func refreshLoginItemLocation() {
        let path = Bundle.main.bundlePath
        guard launchAtLogin, UserDefaults.standard.string(forKey: Self.loginItemPathKey) != path else { return }
        try? SMAppService.mainApp.unregister()
        try? SMAppService.mainApp.register()
        UserDefaults.standard.set(path, forKey: Self.loginItemPathKey)
    }

    func restoreDefaults() {
        var defaults = EQSettings()
        defaults.enabled = settings.enabled
        settings = defaults
    }

    func quit() {
        pipeline.stop()
        NSApp.terminate(nil)
    }

    private func start() {
        do {
            try pipeline.start(settings: settings)
            status = "On → \(pipeline.outputDeviceName) · \(Int(pipeline.sampleRate)) Hz"
        } catch {
            status = error.localizedDescription
        }
    }

    private func stop() {
        pipeline.stop()
        status = "Off — audio plays unprocessed"
    }

    /// Device switches arrive as bursts of notifications; rebuild once things settle.
    private func scheduleRestart() {
        guard settings.enabled else { return }
        restartWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.start() }
        }
        restartWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    private func observeDefaultOutput() {
        var address = CA.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(CA.system, &address, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.scheduleRestart() }
        }
    }
}
