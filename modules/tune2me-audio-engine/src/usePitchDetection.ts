import { useCallback, useEffect, useState } from 'react';
import Tune2MeAudioEngine, { PitchDetectedEvent } from './Tune2MeAudioEngineModule';
import { subscribeToPitch, subscribeToRouteChange } from './pitchEventBus';

export function usePitchDetection() {
  const [latestPitch, setLatestPitch] = useState<PitchDetectedEvent | null>(null);
  const [inputPortName, setInputPortName] = useState<string | null>(null);
  const [isListening, setIsListening] = useState(false);
  const [lastError, setLastError] = useState<string | null>(null);

  useEffect(() => {
    const unsubscribePitch = subscribeToPitch(setLatestPitch);
    const unsubscribeRoute = subscribeToRouteChange((event) => setInputPortName(event.portName));
    return () => {
      unsubscribePitch();
      unsubscribeRoute();
    };
  }, []);

  // Caught explicitly rather than left to reject unhandled — a native
  // AsyncFunction rejection reaching a bare `await` in an onPress handler
  // is exactly the kind of thing that can surface as a hard-to-diagnose
  // crash-like failure in a Release build (no error UI, per AGENTS.md).
  const start = useCallback(async () => {
    try {
      await Tune2MeAudioEngine.startListening();
      setIsListening(true);
      setInputPortName(Tune2MeAudioEngine.getCurrentInputPortName());
      setLastError(null);
    } catch (error) {
      setLastError(error instanceof Error ? error.message : String(error));
    }
  }, []);

  const stop = useCallback(() => {
    Tune2MeAudioEngine.stopListening();
    setIsListening(false);
  }, []);

  return { latestPitch, inputPortName, isListening, lastError, start, stop };
}
