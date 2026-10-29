import AVFoundation
import CoreAudio
import Foundation

/// Preallocated buffers shared by the HAL IO thread and the engine's source node,
/// so nothing on the render path allocates.
final class RenderScratch {
    static let maxFrames = 4096

    let inL: UnsafeMutablePointer<Float>
    let inR: UnsafeMutablePointer<Float>
    let outL: UnsafeMutablePointer<Float>
    let outR: UnsafeMutablePointer<Float>
    let renderList: UnsafeMutableAudioBufferListPointer
    var frames = 0
    /// Input channels the output device itself contributes to the aggregate, ahead of the tap's channels.
    var inputChannelOffset = 0

    private static func buffer() -> UnsafeMutablePointer<Float> {
        let pointer = UnsafeMutablePointer<Float>.allocate(capacity: maxFrames)
        pointer.initialize(repeating: 0, count: maxFrames)
        return pointer
    }

    init() {
        inL = Self.buffer()
        inR = Self.buffer()
        outL = Self.buffer()
        outR = Self.buffer()
        renderList = AudioBufferList.allocate(maximumBuffers: 2)
    }

    deinit {
        [inL, inR, outL, outR].forEach { $0.deallocate() }
        free(renderList.unsafeMutablePointer)
    }
}

/// System audio → process tap (original output muted) → EQ → reverb → limiter → output device.
/// The tap and the output device share one private aggregate device, so a single IOProc
/// reads the tapped audio and writes the processed result on the same clock.
final class AudioPipeline {
    var onConfigurationChange: (() -> Void)?
    private(set) var outputDeviceName = ""
    private(set) var sampleRate: Double = 0

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var engine: AVAudioEngine?
    private var eq: AVAudioUnitEQ?
    private var reverb: AVAudioUnitReverb?
    private var limiter: AVAudioUnitEffect?
    private var loadedReverbPreset: Int?
    private var rateListener: (device: AudioObjectID, block: AudioObjectPropertyListenerBlock)?
    private let scratch = RenderScratch()
    /// Processed output, for the visuals.
    let samples = SampleRing()

    func start(settings: EQSettings) throws {
        stop()
        do {
            try startPipeline(settings: settings)
        } catch {
            stop()
            throw error
        }
    }

    private func startPipeline(settings: EQSettings) throws {
        let output = try CA.defaultOutputDevice()
        let outputUID = try CA.string(output, kAudioDevicePropertyDeviceUID)
        outputDeviceName = (try? CA.string(output, kAudioObjectPropertyName)) ?? "output"
        let ownProcess = try CA.ownProcessObject()

        let tap = CATapDescription(stereoGlobalTapButExcludeProcesses: [ownProcess])
        tap.uuid = UUID()
        tap.name = "Railgun"
        tap.isPrivate = true
        tap.muteBehavior = .mutedWhenTapped
        try check(AudioHardwareCreateProcessTap(tap, &tapID), "Creating the system audio tap")

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Railgun",
            kAudioAggregateDeviceUIDKey: "Railgun-\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: tap.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
        ]
        try check(AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID), "Creating the output device")

        sampleRate = try CA.value(aggregateID, kAudioDevicePropertyNominalSampleRate, initial: Float64(0))
        scratch.inputChannelOffset = CA.channelCount(output, scope: kAudioObjectPropertyScopeInput)
        let render = try makeEngine(sampleRate: sampleRate)
        apply(settings)

        let scratch = self.scratch
        let samples = self.samples
        try check(AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil) { _, input, _, output, _ in
            AudioPipeline.process(input: input, output: output, scratch: scratch, samples: samples, render: render)
        }, "Creating the audio callback")
        try check(AudioDeviceStart(aggregateID, procID), "Starting audio")
        watchSampleRate(of: output)
    }

    func stop() {
        if let listener = rateListener {
            var address = CA.address(kAudioDevicePropertyNominalSampleRate)
            AudioObjectRemovePropertyListenerBlock(listener.device, &address, .main, listener.block)
            rateListener = nil
        }
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        engine?.stop()
        engine = nil
        eq = nil
        reverb = nil
        limiter = nil
        loadedReverbPreset = nil
    }

    func apply(_ settings: EQSettings) {
        guard let eq, let reverb, let limiter else { return }
        eq.globalGain = settings.preamp
        for (index, band) in eq.bands.enumerated() {
            let frequency = EQSettings.frequencies[index]
            band.filterType = .parametric
            band.frequency = frequency
            band.bandwidth = 1
            band.gain = settings.gains[index]
            // Bands at or above Nyquist (e.g. 16 kHz on a low-rate Bluetooth link) can't be realised.
            band.bypass = Double(frequency) >= sampleRate * 0.45
        }
        eq.bypass = !settings.eqEnabled

        if loadedReverbPreset != settings.reverbPreset,
           let preset = AVAudioUnitReverbPreset(rawValue: settings.reverbPreset) {
            reverb.loadFactoryPreset(preset)
            loadedReverbPreset = settings.reverbPreset
        }
        reverb.wetDryMix = settings.reverbMix
        reverb.bypass = !settings.reverbEnabled

        limiter.bypass = !settings.limiterEnabled
    }

    private func makeEngine(sampleRate: Double) throws -> AVAudioEngineManualRenderingBlock {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            throw CoreAudioError(status: -1, action: "Creating a \(Int(sampleRate)) Hz audio format")
        }
        let engine = AVAudioEngine()
        try engine.enableManualRenderingMode(.realtime, format: format,
                                             maximumFrameCount: AVAudioFrameCount(RenderScratch.maxFrames))

        let scratch = self.scratch
        let source = AVAudioSourceNode(format: format) { _, _, frameCount, list in
            let frames = min(Int(frameCount), scratch.frames)
            for (index, buffer) in UnsafeMutableAudioBufferListPointer(list).enumerated() {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                data.update(from: index == 0 ? scratch.inL : scratch.inR, count: frames)
            }
            return noErr
        }
        let eq = AVAudioUnitEQ(numberOfBands: EQSettings.frequencies.count)
        let reverb = AVAudioUnitReverb()
        let limiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0))

        for node in [source, eq, reverb, limiter] as [AVAudioNode] { engine.attach(node) }
        engine.connect(source, to: eq, format: format)
        engine.connect(eq, to: reverb, format: format)
        engine.connect(reverb, to: limiter, format: format)
        engine.connect(limiter, to: engine.mainMixerNode, format: format)
        engine.prepare()
        try engine.start()

        self.engine = engine
        self.eq = eq
        self.reverb = reverb
        self.limiter = limiter
        return engine.manualRenderingBlock
    }

    private func watchSampleRate(of device: AudioObjectID) {
        var address = CA.address(kAudioDevicePropertyNominalSampleRate)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.onConfigurationChange?() }
        if AudioObjectAddPropertyListenerBlock(device, &address, .main, block) == noErr {
            rateListener = (device, block)
        }
    }

    /// Runs on the HAL IO thread: deinterleave the tap's audio, render it through the engine,
    /// and interleave the result into the output device's buffers.
    private static func process(input: UnsafePointer<AudioBufferList>,
                                output: UnsafeMutablePointer<AudioBufferList>,
                                scratch: RenderScratch,
                                samples: SampleRing,
                                render: AVAudioEngineManualRenderingBlock) {
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        guard outputs.count > 0 else { return }
        let firstChannels = max(Int(outputs[0].mNumberChannels), 1)
        let frames = min(Int(outputs[0].mDataByteSize) / (4 * firstChannels), RenderScratch.maxFrames)
        for buffer in outputs {
            if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
        }
        guard frames > 0 else { return }

        scratch.inL.update(repeating: 0, count: frames)
        scratch.inR.update(repeating: 0, count: frames)
        var channel = -scratch.inputChannelOffset
        var tapChannels = 0
        for buffer in UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)) {
            let count = Int(buffer.mNumberChannels)
            defer { channel += count }
            guard count > 0, let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let available = min(frames, Int(buffer.mDataByteSize) / (4 * count))
            for offset in 0..<count {
                let target = channel + offset
                guard target == 0 || target == 1 else { continue }
                let destination = target == 0 ? scratch.inL : scratch.inR
                for frame in 0..<available { destination[frame] = data[frame * count + offset] }
                tapChannels = max(tapChannels, target + 1)
            }
        }
        if tapChannels == 1 { scratch.inR.update(from: scratch.inL, count: frames) }

        scratch.frames = frames
        let list = scratch.renderList
        list[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * 4), mData: UnsafeMutableRawPointer(scratch.outL))
        list[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * 4), mData: UnsafeMutableRawPointer(scratch.outR))
        var error: OSStatus = noErr
        guard render(AVAudioFrameCount(frames), list.unsafeMutablePointer, &error) == .success,
              let left = list[0].mData?.assumingMemoryBound(to: Float.self),
              let right = list[1].mData?.assumingMemoryBound(to: Float.self) else { return }
        samples.write(left: left, right: right, frames: frames)

        var outChannel = 0
        for buffer in outputs {
            let count = Int(buffer.mNumberChannels)
            defer { outChannel += count }
            guard count > 0, let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            for offset in 0..<count {
                let target = outChannel + offset
                guard target < 2 else { continue }
                let source = target == 0 ? left : right
                for frame in 0..<frames { data[frame * count + offset] = source[frame] }
            }
        }
    }
}
