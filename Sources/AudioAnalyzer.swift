import Accelerate
import Foundation

/// Lock-free mono ring buffer: the HAL IO thread writes processed audio, the visuals read the
/// most recent window. Torn reads are harmless for visuals, so there is no locking.
final class SampleRing {
    static let capacity = 8192
    private static let mask = capacity - 1
    private let buffer: UnsafeMutablePointer<Float>
    private let writeIndex: UnsafeMutablePointer<Int>

    init() {
        buffer = .allocate(capacity: Self.capacity)
        buffer.initialize(repeating: 0, count: Self.capacity)
        writeIndex = .allocate(capacity: 1)
        writeIndex.initialize(to: 0)
    }

    deinit {
        buffer.deallocate()
        writeIndex.deallocate()
    }

    func write(left: UnsafePointer<Float>, right: UnsafePointer<Float>, frames: Int) {
        var index = writeIndex.pointee
        for frame in 0..<frames {
            buffer[index & Self.mask] = (left[frame] + right[frame]) * 0.5
            index += 1
        }
        writeIndex.pointee = index
    }

    /// Copies the latest `count` samples into `destination` and returns the write position,
    /// which callers compare between reads to notice when audio has stopped flowing.
    @discardableResult
    func read(into destination: UnsafeMutablePointer<Float>, count: Int) -> Int {
        let end = writeIndex.pointee
        for offset in 0..<count { destination[offset] = buffer[(end - count + offset) & Self.mask] }
        return end
    }
}

/// What a visual effect gets each frame. All values are normalised to 0...1.
struct AudioFeatures {
    static let bandCount = 48

    var bands = [Float](repeating: 0, count: bandCount)  // log-spaced 40 Hz – 16 kHz
    var level: Float = 0
    var bass: Float = 0
    var treble: Float = 0
    var beat = false          // true on the frame a beat is detected
    var beatPulse: Float = 0  // jumps to 1 on a beat, then decays
}

/// Turns the sample ring into spectrum bands and beat events, once per display frame.
final class AudioAnalyzer {
    private static let fftSize = 1024
    private let ring: SampleRing
    private let sampleRate: () -> Double
    private let fft = vDSP.FFT(log2n: vDSP_Length(10), radix: .radix2, ofType: DSPSplitComplex.self)!
    private let window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized,
                                     count: AudioAnalyzer.fftSize, isHalfWindow: false)
    private var samples = [Float](repeating: 0, count: AudioAnalyzer.fftSize)
    private var real = [Float](repeating: 0, count: AudioAnalyzer.fftSize / 2)
    private var imaginary = [Float](repeating: 0, count: AudioAnalyzer.fftSize / 2)
    private var power = [Float](repeating: 0, count: AudioAnalyzer.fftSize / 2)

    private var lastWrite = -1
    private var peakDB: Float = -40
    private var bassHistory = [Float](repeating: 0, count: 45)
    private var bassHistoryIndex = 0
    private var sinceBeat: Double = 1
    private(set) var features = AudioFeatures()

    /// Higher = beats trigger more easily.
    var sensitivity: Float = 0.5

    init(ring: SampleRing, sampleRate: @escaping () -> Double) {
        self.ring = ring
        self.sampleRate = sampleRate
    }

    func update(dt: Double) {
        sinceBeat += dt
        let write = samples.withUnsafeMutableBufferPointer { ring.read(into: $0.baseAddress!, count: $0.count) }
        let flowing = write != lastWrite
        lastWrite = write
        let rate = sampleRate()
        guard flowing, rate > 0 else { decay(dt: dt); return }

        computePower()
        let binHz = Float(rate) / Float(Self.fftSize)
        var next = features
        next.beat = false

        // Log-spaced bands, auto-gained against a slowly falling peak so quiet music still moves.
        var frameMax: Float = -120
        var bandDB = [Float](repeating: -120, count: AudioFeatures.bandCount)
        for band in 0..<AudioFeatures.bandCount {
            let low = 40 * pow(400, Float(band) / Float(AudioFeatures.bandCount))
            let high = 40 * pow(400, Float(band + 1) / Float(AudioFeatures.bandCount))
            let first = max(1, Int(low / binHz))
            let last = min(power.count - 1, max(first, Int(high / binHz)))
            var total: Float = 0
            for bin in first...last { total += power[bin] }
            let db = 10 * log10(total / Float(last - first + 1) + 1e-12)
            bandDB[band] = db
            frameMax = max(frameMax, db)
        }
        peakDB = max(peakDB - Float(dt) * 6, frameMax, -60)
        let attack = Float(min(1, dt * 30)), release = Float(min(1, dt * 8))
        for band in 0..<AudioFeatures.bandCount {
            let value = min(max((bandDB[band] - (peakDB - 45)) / 45, 0), 1)
            let smoothing = value > next.bands[band] ? attack : release
            next.bands[band] += (value - next.bands[band]) * smoothing
        }
        let bandCount = AudioFeatures.bandCount
        next.bass = average(next.bands[0..<bandCount / 6])
        next.treble = average(next.bands[(bandCount * 2 / 3)...])
        next.level = average(next.bands[...])

        // Beat: low-end energy jumping well above its recent average.
        var bassEnergy: Float = 0
        for bin in max(1, Int(40 / binHz))...max(1, Int(160 / binHz)) { bassEnergy += power[bin] }
        let mean = bassHistory.reduce(0, +) / Float(bassHistory.count)
        bassHistory[bassHistoryIndex] = bassEnergy
        bassHistoryIndex = (bassHistoryIndex + 1) % bassHistory.count
        let threshold = 1.7 - sensitivity * 0.6
        if bassEnergy > mean * threshold, bassEnergy > 1e-6, sinceBeat > 0.2 {
            next.beat = true
            next.beatPulse = 1
            sinceBeat = 0
        } else {
            next.beatPulse = max(0, next.beatPulse - Float(dt) * 3.5)
        }
        features = next
    }

    private func decay(dt: Double) {
        let factor = Float(max(0, 1 - dt * 4))
        for band in features.bands.indices { features.bands[band] *= factor }
        features.level *= factor
        features.bass *= factor
        features.treble *= factor
        features.beat = false
        features.beatPulse = max(0, features.beatPulse - Float(dt) * 3.5)
    }

    private func computePower() {
        vDSP.multiply(samples, window, result: &samples)
        real.withUnsafeMutableBufferPointer { realPointer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imaginaryPointer.baseAddress!)
                samples.withUnsafeBytes { raw in
                    vDSP_ctoz(raw.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(Self.fftSize / 2))
                }
                fft.forward(input: split, output: &split)
                vDSP.squareMagnitudes(split, result: &power)
            }
        }
    }

    private func average<C: Collection>(_ values: C) -> Float where C.Element == Float {
        values.isEmpty ? 0 : values.reduce(0, +) / Float(values.count)
    }
}
