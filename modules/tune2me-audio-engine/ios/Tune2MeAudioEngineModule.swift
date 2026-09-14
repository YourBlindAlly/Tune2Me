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
//   2. No VoiceOver volume ducking while listening. On-device testing
//      2026-09-14 found this is NOT ordinary ducking (one thing quiets
//      while another plays) — it's a uniform drop in ALL output, our own
//      tone and VoiceOver's speech both, and it persisted indefinitely.
//      Three compounding causes, all addressed: missing ".mixWithOthers";
//      the engine/session never being torn down (teardownEngineIfIdle());
//      and, confirmed via research to match a real, independently-
//      documented iOS platform behavior (github.com/godotengine/godot/
//      issues/88893, developer.apple.com/forums/thread/820613),
//      .playAndRecord itself routes audio through a reduced "phone call"
//      style volume ceiling that no session option removes — the only fix
//      is not using .playAndRecord when recording isn't actually needed
//      (see needsRecording throughout this file). Needs re-testing.
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
    private var configChangeObserver: NSObjectProtocol?
    private var isDroneModeActive = false

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

            // Enabling voice processing (drone mode) can make AVAudioEngine
            // stop itself as a side effect of the internal graph changing —
            // confirmed via research, not something preventable, only
            // reactable-to. Without this observer, drone mode would go
            // silent immediately after starting.
            self.configChangeObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange,
                object: self.engine,
                queue: .main
            ) { [weak self] _ in
                self?.handleEngineConfigurationChange()
            }
        }

        AsyncFunction("startListening") { () throws -> Void in
            guard !self.isDroneModeActive else { return }
            try self.startListening()
        }

        Function("stopListening") {
            guard !self.isDroneModeActive else { return }
            self.stopListening()
            self.teardownEngineIfIdle()
        }

        AsyncFunction("playTone") { (frequencyHz: Double, durationSeconds: Double) throws -> Void in
            guard !self.isDroneModeActive else { return }
            // Only request recording capability if we're already listening
            // (Mode 3's simultaneous play+listen). A standalone tone (Mode
            // 1, mic never touched) uses .playback instead of
            // .playAndRecord - see ensureEngineRunning()/configureSession().
            try self.ensureEngineRunning(needsRecording: self.isListening)
            self.toneGenerator.play(frequencyHz: frequencyHz, durationSeconds: durationSeconds)
        }

        Function("stopTone") {
            guard !self.isDroneModeActive else { return }
            self.toneGenerator.stop()
            self.teardownEngineIfIdle()
        }

        Function("getCurrentInputPortName") { () -> String? in
            AVAudioSession.sharedInstance().currentRoute.inputs.first?.portName
        }

        // Mode 3's "drone" experiment: play a reference tone continuously
        // WHILE listening, rather than play-then-listen sequentially. This
        // needs .voiceChat mode (not .measurement) plus Apple's Voice
        // Processing I/O (the same mechanism a real phone call uses to
        // stay loud while two-way) — .measurement mode is deliberately
        // quiet for output by Apple's own design (see configureSession's
        // comment), which is fine for Mode 2's listen-only case but not
        // for playing a tone the user needs to actually hear. Genuinely
        // unproven territory - needs real on-device testing for both
        // volume AND whether echo cancellation distorts pitch detection
        // of the user's actual note.
        AsyncFunction("startDroneListening") { (frequencyHz: Double) throws -> Void in
            try self.startDroneListening(frequencyHz: frequencyHz)
        }

        Function("stopDroneListening") {
            self.stopDroneListening()
        }

        OnDestroy {
            if let observer = self.routeObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            if let observer = self.configChangeObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            self.stopListening()
            self.stopDroneListening()
        }
    }

    // MARK: - Session configuration

    private func configureSession(needsRecording: Bool) throws {
        let session = AVAudioSession.sharedInstance()
        if needsRecording {
            // .measurement mode avoids the DSP-driven part of the
            // VoiceOver-ducking problem (echo cancellation / AGC distorting
            // both pitch analysis and other audio), and .mixWithOthers
            // avoids the "active session claims priority" ducking. But
            // .playAndRecord itself carries a real, confirmed-on-device and
            // independently-documented iOS platform limitation on top of
            // both of those: it routes ALL audio - our own tone, AND
            // VoiceOver's speech, everything - through a reduced "phone
            // call" style volume ceiling, not just a relative duck of one
            // thing against another (confirmed 2026-09-14; matches
            // github.com/godotengine/godot/issues/88893 and
            // developer.apple.com/forums/thread/820613, both reporting the
            // same category-level volume ceiling). There's no session
            // option that undoes this - the only fix is to not use
            // .playAndRecord at all when recording isn't actually needed
            // (see needsRecording above).
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.mixWithOthers, .allowBluetoothA2DP, .defaultToSpeaker]
            )
        } else {
            // Mode 1 (reference tone, mic never touched) doesn't need
            // .playAndRecord at all - .playback stays at full media volume
            // with no reduced-ceiling behavior.
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        }
        try session.setActive(true)
        if needsRecording {
            try preferBuiltInMic(session: session)
        }
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

    // Tracks which category the session is currently configured for, so a
    // later call that needs recording (e.g. Mode 3 starting to listen
    // while a Mode-1-style tone session is already running) can upgrade
    // from .playback to .playAndRecord - and so a call that only needs
    // playback doesn't unnecessarily pay .playAndRecord's volume-ceiling
    // cost when nothing is actually recording.
    private var recordingCapable = false

    private func ensureEngineRunning(needsRecording: Bool) throws {
        if engine.isRunning && (recordingCapable || !needsRecording) { return }
        if engine.isRunning { engine.stop() }
        try configureSession(needsRecording: needsRecording)
        attachSourceNodeIfNeeded()
        engine.prepare()
        try engine.start()
        recordingCapable = needsRecording
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
        try ensureEngineRunning(needsRecording: true)

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

    // MARK: - Drone mode (Mode 3, simultaneous play + listen)

    private func startDroneListening(frequencyHz: Double) throws {
        guard !isListening, !isDroneModeActive else { return }

        // .voiceChat (not .measurement) keeps full output volume, matching
        // how a real phone call stays loud while two-way — see
        // configureSession()'s comment for why .measurement can't do this.
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.mixWithOthers, .allowBluetoothA2DP, .defaultToSpeaker]
        )
        try session.setActive(true)
        try preferBuiltInMic(session: session)

        if engine.isRunning { engine.stop() }
        recordingCapable = false

        // Order matters here (confirmed via research): the playback graph
        // must exist BEFORE voice processing is enabled, or its echo
        // cancellation has no reference for "what the speaker is playing"
        // and never removes our own tone from the mic signal.
        attachSourceNodeIfNeeded()
        try engine.inputNode.setVoiceProcessingEnabled(true)
        try engine.outputNode.setVoiceProcessingEnabled(true)

        engine.prepare()
        try engine.start()
        recordingCapable = true

        // format: nil for the same reason as startListening() — see that
        // function's comment. Voice processing also changes the input
        // buffer's channel count (reportedly 1 -> 5) - reading channel 0
        // via floatChannelData[0] (in processInputBuffer) should still be
        // the processed mono voice signal regardless, but this needs
        // confirming on-device, not just assumed.
        engine.inputNode.installTap(onBus: 0, bufferSize: 2048, format: nil) { [weak self] buffer, _ in
            self?.processInputBuffer(buffer, sampleRate: buffer.format.sampleRate)
        }

        toneGenerator.playSustained(frequencyHz: frequencyHz)
        isListening = true
        isDroneModeActive = true
    }

    private func stopDroneListening() {
        guard isDroneModeActive else { return }
        toneGenerator.stop()
        if isListening {
            engine.inputNode.removeTap(onBus: 0)
            isListening = false
        }
        if engine.inputNode.isVoiceProcessingEnabled {
            try? engine.inputNode.setVoiceProcessingEnabled(false)
        }
        if engine.outputNode.isVoiceProcessingEnabled {
            try? engine.outputNode.setVoiceProcessingEnabled(false)
        }
        isDroneModeActive = false
        engine.stop()
        recordingCapable = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func handleEngineConfigurationChange() {
        // Enabling voice processing (or other engine-graph changes) can
        // stop the engine out from under us - confirmed via research as a
        // known AVAudioEngine behavior, not preventable, only reactable
        // to. Restart it if it's supposed to be running.
        guard !engine.isRunning, isListening || toneGenerator.isActive else { return }
        engine.prepare()
        try? engine.start()
    }

    // Without this, the engine and session stay active indefinitely after
    // the first playTone()/startListening() call — confirmed on-device:
    // VoiceOver stayed ducked for the rest of the app's life, and "Stop
    // Tone" did nothing, because stopping tone playback alone never
    // deactivated the session that was actually causing the ducking.
    private func teardownEngineIfIdle() {
        guard !isListening, !toneGenerator.isActive, engine.isRunning else { return }
        engine.stop()
        recordingCapable = false
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
