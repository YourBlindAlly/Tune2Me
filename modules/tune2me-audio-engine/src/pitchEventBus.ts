import Tune2MeAudioEngine, { InputRouteChangedEvent, PitchDetectedEvent } from './Tune2MeAudioEngineModule';

// One real native `addListener` call for the app's whole lifetime, fanned
// out to a JS Set of subscribers. This makes native-level listener
// duplication structurally impossible regardless of how many components
// mount/remount/fail to clean up — the alternative (every hook calling
// addListener directly) is a real bug class: an imperfectly-unmounted
// component leaves a stale listener attached, and the same native event
// then fires once per still-attached listener, which looks exactly like
// "this is happening twice" everywhere downstream.
type Listener<T> = (event: T) => void;

function createEventBus<T>() {
  const subscribers = new Set<Listener<T>>();
  return {
    subscribe(listener: Listener<T>): () => void {
      subscribers.add(listener);
      return () => {
        subscribers.delete(listener);
      };
    },
    emit(event: T): void {
      subscribers.forEach((listener) => listener(event));
    },
  };
}

const pitchBus = createEventBus<PitchDetectedEvent>();
const routeBus = createEventBus<InputRouteChangedEvent>();

let nativeListenersAttached = false;

function ensureNativeListenersAttached(): void {
  if (nativeListenersAttached) return;
  nativeListenersAttached = true;
  Tune2MeAudioEngine.addListener('onPitchDetected', (event) => pitchBus.emit(event));
  Tune2MeAudioEngine.addListener('onInputRouteChanged', (event) => routeBus.emit(event));
}

export function subscribeToPitch(listener: Listener<PitchDetectedEvent>): () => void {
  ensureNativeListenersAttached();
  return pitchBus.subscribe(listener);
}

export function subscribeToRouteChange(listener: Listener<InputRouteChangedEvent>): () => void {
  ensureNativeListenersAttached();
  return routeBus.subscribe(listener);
}
