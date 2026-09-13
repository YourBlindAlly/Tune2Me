Instrument Tuner App: Early Spec

Overview

An iOS instrument tuner app with an accessibility first design, built around VoiceOver support and low vision friendly visuals. The app has three modes: a reference tone mode, a live microphone pitch detection mode, and a guided "tune to me" mode that combines the two. Working name candidates: Open Ear Tuner, PitchGuide, Tune 2 Me. None finalized yet.

Core Requirements

The app must use the phone's own built in microphone for live tuning even when wired or Bluetooth headphones are connected, rather than defaulting to the headphones' microphone. This should use AVAudioSession's input selection to explicitly choose the built in mic from available inputs, overriding the system default.

The app must be fully accessible with VoiceOver throughout.

Audio session configuration should use measurement mode rather than voice chat or default mode. Voice chat and default modes apply voice optimized signal processing, echo cancellation, noise suppression, automatic gain adjustment, which changes how other audio, including VoiceOver speech and reference tones, sounds through the speaker while the mic is active. Measurement mode applies minimal signal processing and is the correct choice for accurate pitch analysis. A known problem in an existing competitor app, Talking Tuner, is that VoiceOver's spoken volume drops dramatically while its microphone is active, requiring the phone volume to be turned way up. This app should avoid that failure mode specifically.

Mode 1: Reference Tone Mode

The microphone is off during this mode. Basic interaction flow: the user chooses an instrument type first, then the screen displays a button for each string or pitch for that instrument, and tapping a button plays that reference tone.

Reference tone sound should start as a clean tone, not a pure sine wave, but something with a bit more character to it.

Instruments to support out of the gate: guitar, bass, ukulele, violin, mandolin, mandola, banjo, lute, cello, and viola.

Tuning support: standard tunings are the priority and ship first. Alternate tunings should start as a curated list of common alternates (for example drop D), with the ability for users to create and save their own custom tunings as a future feature.

The app should remember the last instrument used and open directly to it, rather than always starting on a selection screen.

Mode 2: Live Mic Pitch Detection Mode

The phone listens via the built in mic and gives real time feedback as the user plays.

Visual display should be simple and recognizable, not visually fancy, since VoiceOver support is the priority over visual polish. Include a low vision friendly visual: large icons, plus a full screen color change as a tuning indicator, the whole screen turns green when in tune and red when not yet in tune.

Audio feedback: the app should announce the detected pitch and how sharp or flat it is out loud through VoiceOver as the user plays (for example, "five cents sharp"), plus play a distinct short confirmation sound, like a small beep or pluck, when the note is confirmed in tune. The in tune confirmation sound should be played at the actual frequency being tuned to, rather than a generic beep pitch.

Mode 3: "Tune to Me" / Play and Listen Mode

This mode merges the reference tone and live mic concepts: the app plays the reference pitch being tuned to, like another instrumentalist giving a pitch, then listens via the mic to check whether the user matched it.

For an instrument like guitar, it starts by playing one string's reference pitch, and as soon as the user is in tune on that string, it automatically advances to play the next string's reference pitch, continuing through all strings in order, a fully guided walkthrough.

This mode should rely on tuning by ear against the played reference tone plus the in tune confirmation sound, rather than spoken cents feedback. This is a deliberate choice: it sidesteps needing to hear VoiceOver speak while the mic is actively listening, avoiding the volume ducking problem entirely for this mode.

This mode should also include the on screen visual display (the green and red full screen indicator) for sighted or partially sighted users, same as mode 2.

Mode Switching

The two primary modes (reference tone and live mic) are mutually exclusive; the microphone is expected to be off while reference tones are playing on their own.

Switching between modes should be a simple toggle at the top of the screen. For VoiceOver users, this toggle should be operated via a swipe command rather than tapping a button.

Tips and Hardware Notes (for in app help text, not features to build)

Placing the phone directly against the guitar body can transmit vibration acoustically through the wood to the built in mic, helping pitch detection stay accurate in loud environments, as a lower tech alternative to a true contact pickup.

Possible future hardware compatibility item: an external contact pickup such as the Peterson Pitch Grabber, a clip on active pickup made specifically for mobile tuning apps, could be supported down the line for more accurate pickup in very loud environments.

An iPhone's accelerometer was considered as a vibration based tuning input (similar to how a clip on contact tuner works) but was ruled out: accelerometer based vibration analysis apps are generally built for much lower frequency ranges (often up to around 50 Hz) than instrument pitches (a guitar's low E is around 82 Hz and climbs from there), so this is not a reliable approach with current phone hardware.

Support / Donation Button

Wants a "Donate" or "Support This App" button, likely in the help section, that sends users to an external donation page.

Legal context for the coder: as of recent Apple App Store guideline updates stemming from a United States court decision, apps on the US storefront can include buttons and external links, including a donation link, without needing a special entitlement, as long as the actual transaction happens externally, for example by opening the device browser to a donation page, rather than being processed natively in app. The button label itself (e.g. "Donate") does not appear to be restricted; the requirement is about where the transaction happens, not how clearly it's described.

Open Items / Not Yet Decided

Final app name (candidates: Open Ear Tuner, PitchGuide, Tune 2 Me)
Minimum iOS version target
Full accessibility interaction spec beyond what's described above (VoiceOver rotor behavior, labels, hints, etc. to be detailed during development)
Custom tuning creation UI (future feature, not version one)
