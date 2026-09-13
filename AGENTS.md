# Tune2Me — agent notes

Accessibility-first iOS instrument tuner, built for a blind/VoiceOver-first user. Full spec: [instrument-tuner-app-spec.md](instrument-tuner-app-spec.md). Full build plan (phases, architecture decisions, rationale): see the conversation history / plan artifact from the planning session that started this repo — key points repeated below so they aren't lost.

## Project identity

The app is called **Tune2Me**. Bundle identifier `com.rustyperez.tune2me` (`com.rustyperez.tune2me.preview` for the preview variant). Use `tune2me`/`Tune2Me` for any new file, folder, module, class, or identifier — no other working name.

## Architecture carried over from the sibling project, LyriCue

This app deliberately reuses LyriCue's (`../LyriCue - audio prompter/LyriCue-app`) proven toolchain rather than reinventing it: same Expo/RN/React versions (SDK 57 line), same three-workflow GitHub Actions pipeline (`build-unsigned-ipa.yml` for free-Apple-ID SideStore sideloading, `build-testflight.yml` for signed TestFlight uploads, `build-preview-ipa.yml` for a separate-bundle-ID onboarding-testing variant), same `macos-26` runner + Xcode `26.4` pin (older runners can't compile Expo SDK 57's Swift 6.3 syntax), same local-Expo-module folder shape under `modules/`, same jest-expo test convention (colocated `*.test.ts`, no component tests, config inlined in `package.json`).

**The one genuinely new piece**: a custom native Swift module (`modules/tune2me-audio-engine/`) owning the whole `AVAudioEngine` graph — real-time pitch detection (YIN algorithm) off a mic tap, forced built-in-mic input selection even with headphones connected, `.measurement` audio session mode (not voice-chat/default, which distorts pitch and causes VoiceOver's own speech to duck badly — a named failure mode of a competitor app, "Talking Tuner," this app must avoid), and harmonic-stack tone synthesis for reference tones/confirmation sounds at exact target frequencies. None of this is achievable through `expo-audio`'s JS API alone. This is the single technical risk in the app and must be prototyped and validated on real hardware (four specific on-device checks — mic override, no VoiceOver ducking, pitch accuracy, tone frequency accuracy) before any screen UI is built on top of it.

## Accessibility lessons already learned (from building LyriCue for the same user) — apply directly, don't relearn

- A custom one-finger swipe gesture will NOT reliably reach the app while VoiceOver is on — VoiceOver claims that gesture for its own navigation. The correct mechanism for "swipe to change something while VoiceOver is focused on it" is `accessibilityRole="adjustable"` + `onAccessibilityAction` handling `increment`/`decrement` (VoiceOver's real swipe-up/down-while-focused gesture). This is what the spec's "mode toggle should be swipe-operated for VoiceOver users" requirement actually needs — pair it with a real tappable control too, so it's never swipe-only for a sighted co-user.
- `onAccessibilityAction`/`accessibilityRole="adjustable"` can silently fail to fire when placed directly on a `Text` component (compiles fine, VoiceOver reads the label, but the gesture handler never fires). Always wrap in a `View` and put these props there.
- A frequently-changing on-screen Text element that might hold VoiceOver focus (e.g. a live pitch/cents readout) needs a FIXED, non-content-tracking `accessibilityLabel` — otherwise VoiceOver auto-re-announces its own reading of the changed text on top of the app's own TTS, producing an audible echo.
- Generous `hitSlop` plus actually respecting safe-area insets on every small tap target, especially anything near the top of the screen (closest to the status bar) — an exploring VoiceOver finger can slide off a small target into OS chrome.
- Don't let the app's own TTS race against VoiceOver's automatic screen-transition announcement — gate a screen's first utterance behind an explicit user action rather than auto-speaking on mount.
- A crash in a Release build shows no error UI at all, it just quits — treat "the app just quit" reports like any other uncaught-exception bug, look for a straightforward cause first.
- Async "cancel current, start new" calls (e.g. stop-then-speak, stop-then-listen) need a request-id/generation-counter guard if the wrapping function can be called again before the previous call's await chain resolves, or two overlapping calls can race.
- Centralize any native event listener behind a single in-JS event-bus singleton (one real native `addListener` for the app's lifetime, fanned out to a JS `Set` of subscribers) — don't let multiple components independently subscribe to the same native event, since imperfect unmount cleanup can cause double-firing.

## Expo HAS CHANGED

Read the exact versioned docs at https://docs.expo.dev/versions/v57.0.0/ before writing any code.
