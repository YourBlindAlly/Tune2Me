import ExpoModulesCore
import AVFoundation

// Owns the whole AVAudioEngine graph — both the input tap (pitch detection)
// and output synthesis (reference tone / confirmation pluck) — rather than
// two separate engines/sessions. This matters most for Mode 3 ("Tune to
// Me"), which plays and listens at the same time; two independent engines
// fighting over one AVAudioSession is a real source of bugs.
//
// PHASE 1 PROTOTYPE — see AGENTS.md and the build plan. This is the single
// technical risk in the app and needs validation against real hardware
// before any UI is built on top of it:
//   1. Built-in mic override survives a Bluetooth/wired headphone connect.
//      CONFIRMED WORKING on-device 2026-09-14 (survived a wired headphone
//      connect without falling back to the headphone mic).
//   2. No VoiceOver volume ducking while listening. ".measurement" mode
//      alone was NOT enough — confirmed on-device 2026-09-14 that VoiceOver
//      still ducked dramatically and stayed ducked indefinitely. Root
//      cause was missing ".mixWithOthers" plus the engine/session never
//      being torn down; see configureSession()/teardownEngineIfIdle().
//      Needs re-testing after that fix.
//   3. Pitch accuracy against a known-good reference. Not yet reachable —
//      blocked on the startListening() crash (also fixed 2026-09-14, see
//      installTap's format: nil comment below); needs re-testing.
//   4. Tone character + exact target frequency, by ear. CONFIRMED WORKING
//      on-device 2026-09-14 (a tone played, audibly at the right pitch).
// None of these are verifiable from CI — CI can only prove this compiles.
public class Tune2MeAudioEngineModule: Module {
    private let engine = AVAudioEngine()
    private let toneGenerator = ToneGenerator()
    private var sourceNode: AVAudioSourceNode?
    private var isListening = false
    private var lastEmitTime: TimeInterval = 0
    // ~15Hz is plenty for a tuning UI — no need to emit at audio rate.
    private let minEmitInterval: TimeInterval = 1.0 / 15.0
    private var routeObserver: NSObjectProtocol?

    public func definition() -> ModuleDefinition {
        Name("Tune2MeAudioEngine")

        Events("onPitchDetected", "onInputRouteChanged")

        OnCreate {
            self.routeObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.handleRouteChange()
            }
        }

        AsyncFunction("startListening") { () throws -> Void in
            try self.startListening()
        }

        Function("stopListening") {
            self.stopListening()
            self.teardownEngineIfIdle()
        }

        AsyncFunction("playTone") { (frequencyHz: Double, durationSeconds: Double) throws -> Void in
            try self.ensureEngineRunning()
            self.toneGenerator.play(frequencyHz: frequencyHz, durationSeconds: durationSeconds)
        }

        Function("stopTone") {
            self.toneGenerator.stop()
            self.teardownEngineIfIdle()
        }

        Function("getCurrentInputPortName") { () -> String? in
            AVAudioSession.sharedInstance().currentRoute.inputs.first?.portName
        }

        OnDestroy {
            if let observer = self.routeObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            self.stopListening()
        }
    }

    // MARK: - Session configuration

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        // .measurement mode (not .voiceChat/.default) avoids the DSP-driven
        // part of the VoiceOver-ducking problem (echo cancellation / AGC
        // distorting both pitch analysis and other audio). But mode alone
        // wasn't enough — confirmed on-device: without .mixWithOthers, an
        // active .playAndRecord session tells iOS this app needs audio
        // priority, and VoiceOver's own speech gets ducked as "other
        // audio" exactly like the "Talking Tuner" bug this app exists to
        // avoid. .mixWithOthers is what actually stops that.
        try session.setCategory(
            .playAndRecord,
            mode: .measurement,
            options: [.mixWithOthers, .allowBluetoothA2DP, .defaultToSpeaker]
        )
        try session.setActive(true)
        try preferBuiltInMic(session: session)
    }

    private func preferBuiltInMic(session: AVAudioSession) throws {
        guard let builtInMic = session.availableInputs?.first(where: { $0.portType == .builtInMic }) else {
            // No built-in mic reported as available — nothing to prefer.
            // Shouldn't happen on a real iPhone/iPad, but don't crash if it
            // does; the caller just keeps whatever input is currently active.
            return
        }
        try session.setPreferredInput(builtInMic)
    }

    private func handleRouteChange() {
        let session = AVAudioSession.sharedInstance()
        // Plugging/unplugging headphones can silently reset the preferred
        // input, so this has to be re-asserted on every route change, not
        // just once at startup.
        try? preferBuiltInMic(session: session)

        let input = session.currentRoute.inputs.first
        sendEvent("onInputRouteChanged", [
            "portType": input?.portType.rawValue ?? "none",
            "portName": input?.portName ?? "None",
        ])
    }

    // MARK: - Engine lifecycle

    private func ensureEngineRunning() throws {
        if engine.isRunning { return }
        try configureSession()
        attachSourceNodeIfNeeded()
        engine.prepare()
        try engine.start()
    }

    private func attachSourceNodeIfNeeded() {
        guard sourceNode == nil else { return }
        let format = engine.outputNode.inputFormat(forBus: 0)
        let sampleRate = format.sampleRate
        let generator = toneGenerator

        let node = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let samples = generator.render(frameCount: Int(frameCount), sampleRate: sampleRate)
            let bufferList = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for buffer in bufferList {
                let outPointer = UnsafeMutableBufferPointer<Float>(buffer)
                for i in 0..<Int(frameCount) {
                    outPointer[i] = i < samples.count ? samples[i] : 0
                }
            }
            return noErr
        }

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        sourceNode = node
    }

    private func startListening() throws {
        guard !isListening else { return }
        try ensureEngineRunning()

        // format: nil (not a pre-computed format) is deliberate — it lets
        // AVAudioEngine use the input bus's own current format. Passing an
        // explicit format queried before the input route is fully settled
        // can be an invalid/zero-channel format, which crashes installTap
        // with a native exception Swift's try/catch cannot catch (this is
        // what caused the app to silently die on Start Listening during
        // Phase 1 on-device testing, 2026-09-14). The actual format is
        // read from each buffer instead.
        engine.inputNode.installTap(onBus: 0, bufferSize: 2048, format: nil) { [weak self] buffer, _ in
            self?.processInputBuffer(buffer, sampleRate: buffer.format.sampleRate)
        }
        isListening = true
    }

    private func stopListening() {
        guard isListening else { return }
        engine.inputNode.removeTap(onBus: 0)
        isListening = false
    }

    // Without this, the engine and session stay active indefinitely after
    // the first playTone()/startListening() call — confirmed on-device:
    // VoiceOver stayed ducked for the rest of the app's life, and "Stop
    // Tone" did nothing, because stopping tone playback alone never
    // deactivated the session that was actually causing the ducking.
    private func teardownEngineIfIdle() {
        guard !isListening, !toneGenerator.isActive, engine.isRunning else { return }
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Pitch detection

    private func processInputBuffer(_ buffer: AVAudioPCMBuffer, sampleRate: Double) {
        let now = Date().timeIntervalSince1970
        guard now - lastEmitTime >= minEmitInterval else { return }
        guard let channelData = buffer.floatChannelData else { return }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))

        var sumSquares: Double = 0
        for sample in samples { sumSquares += Double(sample * sample) }
        let rms = sqrt(sumSquares / Double(frameLength))

        let detector = PitchDetector(sampleRate: sampleRate)
        guard let result = detector.detectPitch(buffer: samples) else { return }

        lastEmitTime = now
        sendEvent("onPitchDetected", [
            "frequencyHz": result.frequencyHz,
            "confidence": result.confidence,
            "rmsLevel": rms,
            "timestamp": now,
        ])
    }
}
