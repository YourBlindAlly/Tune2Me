import Foundation

// Renders a short "plucked" tone at an exact target frequency: a stack of
// the fundamental plus 2nd and 3rd harmonics at decaying amplitude, with a
// fast attack and exponential-ish decay envelope. This is what gives the
// tone "character" beyond a bare sine wave (per spec) while staying cheap
// enough to compute per-sample in a real-time render callback, and it
// serves both the reference tone (longer duration) and the in-tune
// confirmation pluck (short duration) from the same code path — the only
// difference between them is the duration passed in.
//
// NOTE: `render` is called from the audio render thread (see
// Tune2MeAudioEngineModule.swift's AVAudioSourceNode callback). Using an
// NSLock here to guard `activeVoice` is a pragmatic simplification for
// this Phase 1 prototype, not best practice for a real-time audio thread
// (a lock can in principle cause priority inversion / glitches under
// contention). `play`/`stop` are only ever called from user-initiated JS
// actions, which are infrequent and short, so contention should be
// negligible in practice — but if Phase 1's on-device testing turns up any
// audio glitches/dropouts, this is the first place to look, and the fix
// would be a lock-free ring buffer or atomic instead.
final class ToneGenerator {
    private struct Voice {
        let frequencyHz: Double
        let startSample: Double
        let durationSeconds: Double
    }

    // (harmonic multiple, relative amplitude) — fundamental dominant, each
    // overtone quieter than the last.
    private static let harmonics: [(multiple: Double, amplitude: Double)] = [
        (1.0, 1.0),
        (2.0, 0.5),
        (3.0, 0.25),
    ]
    private static let harmonicAmplitudeSum = harmonics.reduce(0) { $0 + $1.amplitude }

    private static let attackSeconds = 0.01
    private static let releaseSeconds = 0.08
    private static let outputGain = 0.3

    private var activeVoice: Voice?
    private var sampleClock: Double = 0
    private let lock = NSLock()

    /// Starts playing `frequencyHz` for `durationSeconds`, replacing
    /// whatever tone (if any) is currently sounding.
    func play(frequencyHz: Double, durationSeconds: Double) {
        lock.lock()
        activeVoice = Voice(frequencyHz: frequencyHz, startSample: sampleClock, durationSeconds: durationSeconds)
        lock.unlock()
    }

    func stop() {
        lock.lock()
        activeVoice = nil
        lock.unlock()
    }

    /// Renders `frameCount` mono samples at `sampleRate`, advancing the
    /// internal sample clock regardless of whether a voice is active (so
    /// a voice's elapsed-time math stays correct across calls).
    func render(frameCount: Int, sampleRate: Double) -> [Float] {
        lock.lock()
        let voice = activeVoice
        let startClock = sampleClock
        lock.unlock()

        var output = [Float](repeating: 0, count: frameCount)

        if let voice = voice {
            for frame in 0..<frameCount {
                let elapsed = (startClock + Double(frame) - voice.startSample) / sampleRate
                guard elapsed >= 0 && elapsed < voice.durationSeconds else { continue }

                var sample: Double = 0
                for harmonic in Self.harmonics {
                    sample += harmonic.amplitude * sin(2 * .pi * voice.frequencyHz * harmonic.multiple * elapsed)
                }
                sample /= Self.harmonicAmplitudeSum

                var envelope = 1.0
                if elapsed < Self.attackSeconds {
                    envelope = elapsed / Self.attackSeconds
                } else if elapsed > voice.durationSeconds - Self.releaseSeconds {
                    envelope = max(0, (voice.durationSeconds - elapsed) / Self.releaseSeconds)
                }

                output[frame] = Float(sample * envelope * Self.outputGain)
            }
        }

        lock.lock()
        sampleClock += Double(frameCount)
        if let voice = activeVoice, (sampleClock - voice.startSample) / sampleRate >= voice.durationSeconds {
            activeVoice = nil
        }
        lock.unlock()

        return output
    }
}
