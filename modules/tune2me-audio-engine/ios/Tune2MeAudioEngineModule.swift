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
//   2. No VoiceOver volume ducking while listening. Multiple rounds of
//      on-device testing 2026-09-14 found: this is NOT ordinary ducking
//      (one thing quiets while another plays), it's a uniform drop in ALL
//      output; it happens on Start Listening ALONE, no tone needed, which
//      is why .measurement mode itself (not just .playAndRecord) is the
//      real culprit — see configureSession()'s comment; and real phone
//      calls stay loud on speakerphone (Rusty's own sharp catch), which is
//      what pointed at .voiceChat's Voice Processing I/O rather than a
//      session-option fix. Currently testing TWO parallel approaches:
//      .default mode for plain listening (Mode 2, no tone playing), and
//      Voice Processing I/O + .voiceChat mode for "drone" mode (Mode 3,
//      tone playing WHILE listening — see startDroneListening()). Neither
//      confirmed working yet.
//   3. Pitch accuracy against a known-good reference. Not yet reachable —
//      blocked on TWO crashes now fixed: the original installTap format
//      crash, and a second crash on a repeated Start Listening caused by
//      reusing a stale cached output format across a stop/restart cycle
//      (see reconnectSourceNodeToCurrentFormat()). Needs re-testing.
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
        // WHILE listening, rather than play-then-listen sequentially.
        // Mode 2's plain .default mode (see configureSession) doesn't
        // force echo cancellation, which is fine when nothing is playing
        // — but here we DO need to play something loud while listening,
        // and without echo cancellation that risks feedback between our
        // own output and the mic. .voiceChat mode + Voice Processing I/O
        // is the real mechanism a phone call uses to solve exactly that.
        // Genuinely unproven territory - needs real on-device testing for
        // both volume AND whether echo cancellation distorts pitch
        // detection of the user's actual note.
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
            // .measurement mode was the original choice here (avoids the
            // DSP-driven part of the VoiceOver-ducking problem — echo
            // cancellation/AGC distorting both pitch analysis and other
            // audio) but confirmed on-device 2026-09-14 that it STILL
            // ducks VoiceOver even with nothing playing, just from
            // listening alone: .measurement mode routes output through a
            // reduced "phone call" style volume ceiling as a deliberate
            // Apple design (it assumes a calibration/measurement app
            // doesn't want its own output loud), and that ceiling applies
            // to ALL system audio output while the session is active, not
            // just ours — VoiceOver's speech included. .default mode
            // doesn't carry that same deliberate quiet-output behavior,
            // and (unlike .voiceChat) doesn't force AGC/echo-cancellation
            // on by itself either — trying it here as the mode that
            // hopefully keeps clean input AND normal volume. Needs
            // re-testing to confirm both halves of that.
            try session.setCategory(
                .playAndRecord,
                mode: .default,
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
        reconnectSourceNodeToCurrentFormat()
        engine.prepare()
        try engine.start()
        recordingCapable = needsRecording
    }

    // Read on the real-time render thread, written from the main thread —
    // in practice safe here because every write happens in
    // reconnectSourceNodeToCurrentFormat(), which always runs BEFORE the
    // engine (re)starts, so the render callback is never actually running
    // concurrently with a write. Not a textbook-guaranteed-atomic setup,
    // but a reasonable simplification for this prototype (same tradeoff
    // already made for ToneGenerator's NSLock — see its own comment).
    private var currentOutputSampleRate: Double = 44100

    private func attachSourceNodeIfNeeded() {
        guard sourceNode == nil else { return }
        let generator = toneGenerator

        let node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self = self else { return noErr }
            let samples = generator.render(frameCount: Int(frameCount), sampleRate: self.currentOutputSampleRate)
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
        sourceNode = node
    }

    // Reconnects the source node using the engine's CURRENT output format,
    // rather than trusting a format cached from whenever the node was
    // first attached. The hardware/session format can genuinely change
    // across a stop/restart cycle (e.g. after a category switch between
    // .playback and .playAndRecord) — reusing a stale format is exactly
    // the kind of mismatch that crashes AVAudioEngine with a native
    // exception Swift's try/catch can't catch. Confirmed on-device
    // 2026-09-14: the app crashed on a second Start Listening after a
    // successful stop, matching this failure mode. Must be called AFTER
    // attachSourceNodeIfNeeded() and BEFORE engine.start(), every time.
    private func reconnectSourceNodeToCurrentFormat() {
        guard let node = sourceNode else { return }
        let format = engine.outputNode.inputFormat(forBus: 0)
        currentOutputSampleRate = format.sampleRate
        engine.connect(node, to: engine.mainMixerNode, format: format)
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
        reconnectSourceNodeToCurrentFormat()

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
