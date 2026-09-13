import Foundation

// YIN pitch detection (de Cheveigné & Kawahara, 2002). Preferred over naive
// autocorrelation because the cumulative-mean-normalized-difference step
// (Step 2 below) specifically corrects the octave-error problems plain
// autocorrelation is prone to for musical pitch tracking.
//
// This file has no Expo/AVFoundation/UIKit dependencies on purpose — it's
// plain Foundation math over a Float sample array, so it can be exercised
// with synthetic sine-wave buffers independently of the audio engine or a
// real device, and unit-tested with XCTest if a test target is wired up
// later (deferred for the Phase 1 prototype — see AGENTS.md).
struct PitchResult {
    let frequencyHz: Double
    let confidence: Double
}

final class PitchDetector {
    private let sampleRate: Double
    // Lower threshold = stricter match required before accepting a
    // candidate period. 0.10-0.20 is the commonly cited working range for
    // monophonic instrument pitch tracking; 0.15 is a reasonable starting
    // point to validate against real playing during Phase 1 testing.
    private let threshold: Double

    init(sampleRate: Double, threshold: Double = 0.15) {
        self.sampleRate = sampleRate
        self.threshold = threshold
    }

    func detectPitch(buffer: [Float]) -> PitchResult? {
        let bufferSize = buffer.count
        let halfBufferSize = bufferSize / 2
        guard halfBufferSize > 2 else { return nil }

        var yinBuffer = [Double](repeating: 0, count: halfBufferSize)

        // Step 1: difference function d(tau) — how well the signal matches
        // itself shifted by tau samples.
        for tau in 0..<halfBufferSize {
            var sum: Double = 0
            for i in 0..<halfBufferSize {
                let delta = Double(buffer[i]) - Double(buffer[i + tau])
                sum += delta * delta
            }
            yinBuffer[tau] = sum
        }

        // Step 2: cumulative mean normalized difference function.
        // Normalizing by the running average (rather than using d(tau)
        // directly) is what suppresses the octave-doubling errors plain
        // autocorrelation is prone to.
        yinBuffer[0] = 1
        var runningSum: Double = 0
        for tau in 1..<halfBufferSize {
            runningSum += yinBuffer[tau]
            yinBuffer[tau] = runningSum == 0 ? 1 : yinBuffer[tau] * Double(tau) / runningSum
        }

        // Step 3: absolute threshold — take the first local minimum below
        // threshold, rather than the global minimum, since the global
        // minimum can land on a spurious short lag.
        var tauEstimate = -1
        var tau = 2
        while tau < halfBufferSize {
            if yinBuffer[tau] < threshold {
                var localTau = tau
                while localTau + 1 < halfBufferSize && yinBuffer[localTau + 1] < yinBuffer[localTau] {
                    localTau += 1
                }
                tauEstimate = localTau
                break
            }
            tau += 1
        }

        guard tauEstimate != -1 else { return nil }

        // Step 4: parabolic interpolation around the chosen tau for a
        // fractional-sample estimate — meaningfully improves accuracy over
        // just using the integer tau, especially at lower guitar-range
        // frequencies where one sample of tau error is a bigger pitch error.
        let betterTau: Double
        if tauEstimate > 0 && tauEstimate < halfBufferSize - 1 {
            let s0 = yinBuffer[tauEstimate - 1]
            let s1 = yinBuffer[tauEstimate]
            let s2 = yinBuffer[tauEstimate + 1]
            let denominator = 2 * (2 * s1 - s2 - s0)
            let adjustment = denominator == 0 ? 0 : (s2 - s0) / denominator
            betterTau = adjustment.isFinite ? Double(tauEstimate) + adjustment : Double(tauEstimate)
        } else {
            betterTau = Double(tauEstimate)
        }

        guard betterTau > 0 else { return nil }

        let frequency = sampleRate / betterTau
        let confidence = max(0, 1.0 - yinBuffer[tauEstimate])
        return PitchResult(frequencyHz: frequency, confidence: confidence)
    }
}
