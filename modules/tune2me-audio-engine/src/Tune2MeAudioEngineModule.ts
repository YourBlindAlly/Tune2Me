import { NativeModule, requireNativeModule } from 'expo';

export type PitchDetectedEvent = {
  frequencyHz: number;
  confidence: number;
  rmsLevel: number;
  timestamp: number;
};

export type InputRouteChangedEvent = {
  portType: string;
  portName: string;
};

export type Tune2MeAudioEngineEvents = {
  onPitchDetected: (event: PitchDetectedEvent) => void;
  onInputRouteChanged: (event: InputRouteChangedEvent) => void;
};

declare class Tune2MeAudioEngineModule extends NativeModule<Tune2MeAudioEngineEvents> {
  startListening(): Promise<void>;
  stopListening(): void;
  playTone(frequencyHz: number, durationSeconds: number): Promise<void>;
  stopTone(): void;
  getCurrentInputPortName(): string | null;
  /** Mode 3's "drone" experiment: plays frequencyHz continuously while listening, using voice processing (echo cancellation) to stay loud. */
  startDroneListening(frequencyHz: number): Promise<void>;
  stopDroneListening(): void;
}

export default requireNativeModule<Tune2MeAudioEngineModule>('Tune2MeAudioEngine');
