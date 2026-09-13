// Tune2Me is iOS-only per spec (real-time pitch detection needs the native
// AVAudioEngine module). This stub exists only so Metro doesn't blow up if
// `expo start --web` is ever run during development — it has no real
// functionality.
import type { InputRouteChangedEvent, PitchDetectedEvent, Tune2MeAudioEngineEvents } from './Tune2MeAudioEngineModule';

type Listener<EventName extends keyof Tune2MeAudioEngineEvents> = Tune2MeAudioEngineEvents[EventName];

const listeners = new Map<keyof Tune2MeAudioEngineEvents, Set<(event: unknown) => void>>();

const stub = {
  async startListening(): Promise<void> {
    console.warn('Tune2MeAudioEngine: pitch detection is not available on web.');
  },
  stopListening(): void {},
  async playTone(_frequencyHz: number, _durationSeconds: number): Promise<void> {
    console.warn('Tune2MeAudioEngine: tone playback is not available on web.');
  },
  stopTone(): void {},
  getCurrentInputPortName(): string | null {
    return null;
  },
  addListener<EventName extends keyof Tune2MeAudioEngineEvents>(eventName: EventName, listener: Listener<EventName>) {
    if (!listeners.has(eventName)) listeners.set(eventName, new Set());
    listeners.get(eventName)!.add(listener as (event: unknown) => void);
    return {
      remove: () => listeners.get(eventName)?.delete(listener as (event: unknown) => void),
    };
  },
};

export default stub;
export type { InputRouteChangedEvent, PitchDetectedEvent };
