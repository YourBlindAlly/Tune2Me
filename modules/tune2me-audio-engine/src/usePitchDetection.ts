import { useCallback, useEffect, useState } from 'react';
import Tune2MeAudioEngine, { PitchDetectedEvent } from './Tune2MeAudioEngineModule';
import { subscribeToPitch, subscribeToRouteChange } from './pitchEventBus';

export function usePitchDetection() {
  const [latestPitch, setLatestPitch] = useState<PitchDetectedEvent | null>(null);
  const [inputPortName, setInputPortName] = useState<string | null>(null);
  const [isListening, setIsListening] = useState(false);

  useEffect(() => {
    const unsubscribePitch = subscribeToPitch(setLatestPitch);
    const unsubscribeRoute = subscribeToRouteChange((event) => setInputPortName(event.portName));
    return () => {
      unsubscribePitch();
      unsubscribeRoute();
    };
  }, []);

  const start = useCallback(async () => {
    await Tune2MeAudioEngine.startListening();
    setIsListening(true);
    setInputPortName(Tune2MeAudioEngine.getCurrentInputPortName());
  }, []);

  const stop = useCallback(() => {
    Tune2MeAudioEngine.stopListening();
    setIsListening(false);
  }, []);

  return { latestPitch, inputPortName, isListening, start, stop };
}
