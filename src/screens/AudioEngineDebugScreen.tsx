import { useState } from 'react';
import { Pressable, StyleSheet, Text, TextInput, View } from 'react-native';
import * as Speech from 'expo-speech';
import Tune2MeAudioEngine from '../../modules/tune2me-audio-engine/src/Tune2MeAudioEngineModule';
import { usePitchDetection } from '../../modules/tune2me-audio-engine/src/usePitchDetection';

// Phase 1 prototype screen — exercises the native audio engine directly so
// the four on-device checks from the build plan can actually be run:
//   1. Built-in mic override survives a headphone/Bluetooth connect.
//   2. No VoiceOver volume ducking while listening.
//   3. Pitch accuracy against a known-good reference.
//   4. Tone character + exact target frequency, by ear.
// Not a real app screen — no styling polish intended, just accessible
// enough to actually run the checks with VoiceOver.
export default function AudioEngineDebugScreen() {
  const { latestPitch, inputPortName, isListening, lastError, start, stop } = usePitchDetection();
  const [toneFrequencyText, setToneFrequencyText] = useState('440');
  const [toneError, setToneError] = useState<string | null>(null);
  const [isDroneActive, setIsDroneActive] = useState(false);
  const [droneError, setDroneError] = useState<string | null>(null);

  // The pitch readout updates up to ~15 times a second. If this Text held
  // a content-tracking accessibilityLabel, VoiceOver would try to
  // re-announce it every update while focused — an unintelligible mess.
  // Instead the label stays fixed, and "Speak Current Reading" reads the
  // latest values once, on demand. See AGENTS.md.
  const speakCurrentReading = () => {
    const parts: string[] = [];
    parts.push(inputPortName ? `Input: ${inputPortName}` : 'Input: unknown');
    if (latestPitch) {
      parts.push(`${latestPitch.frequencyHz.toFixed(1)} hertz`);
      parts.push(`confidence ${(latestPitch.confidence * 100).toFixed(0)} percent`);
      parts.push(`level ${latestPitch.rmsLevel.toFixed(3)}`);
    } else {
      parts.push('No pitch detected yet');
    }
    if (lastError) parts.push(`Last error: ${lastError}`);
    Speech.speak(parts.join(', '), { useApplicationAudioSession: false });
  };

  const handleToggleListening = async () => {
    if (isListening) {
      stop();
    } else {
      await start();
    }
  };

  const playTestTone = async (durationSeconds: number) => {
    const frequency = parseFloat(toneFrequencyText);
    if (!Number.isFinite(frequency) || frequency <= 0) return;
    try {
      await Tune2MeAudioEngine.playTone(frequency, durationSeconds);
      setToneError(null);
    } catch (error) {
      setToneError(error instanceof Error ? error.message : String(error));
    }
  };

  // Mode 3's "drone" experiment — tone plays continuously WHILE listening,
  // using voice processing (echo cancellation) to try to stay loud. See
  // Tune2MeAudioEngineModule.swift's startDroneListening comment.
  const toggleDrone = async () => {
    if (isDroneActive) {
      Tune2MeAudioEngine.stopDroneListening();
      setIsDroneActive(false);
      return;
    }
    const frequency = parseFloat(toneFrequencyText);
    if (!Number.isFinite(frequency) || frequency <= 0) return;
    try {
      await Tune2MeAudioEngine.startDroneListening(frequency);
      setIsDroneActive(true);
      setDroneError(null);
    } catch (error) {
      setDroneError(error instanceof Error ? error.message : String(error));
    }
  };

  return (
    <View style={styles.container}>
      <Text style={styles.title}>Audio Engine Debug</Text>

      <View accessible accessibilityLabel={`Current input: ${inputPortName ?? 'unknown'}`}>
        <Text style={styles.readout}>Input: {inputPortName ?? 'Not listening'}</Text>
      </View>

      <View accessible accessibilityLabel="Live pitch reading — use Speak Current Reading for a spoken value">
        <Text style={styles.readout}>
          {latestPitch
            ? `${latestPitch.frequencyHz.toFixed(1)} Hz  |  confidence ${(latestPitch.confidence * 100).toFixed(0)}%  |  level ${latestPitch.rmsLevel.toFixed(3)}`
            : 'No pitch detected yet'}
        </Text>
      </View>

      {(lastError || toneError || droneError) && (
        <Text style={styles.errorText} accessibilityLiveRegion="polite">
          Error: {lastError ?? toneError ?? droneError}
        </Text>
      )}

      <Pressable
        onPress={handleToggleListening}
        style={styles.button}
        accessibilityRole="button"
        accessibilityLabel={isListening ? 'Stop listening' : 'Start listening'}
        hitSlop={{ top: 14, bottom: 14, left: 14, right: 14 }}
      >
        <Text style={styles.buttonText}>{isListening ? 'Stop Listening' : 'Start Listening'}</Text>
      </Pressable>

      <Pressable
        onPress={speakCurrentReading}
        style={styles.button}
        accessibilityRole="button"
        accessibilityLabel="Speak current reading"
        hitSlop={{ top: 14, bottom: 14, left: 14, right: 14 }}
      >
        <Text style={styles.buttonText}>Speak Current Reading</Text>
      </Pressable>

      <View style={styles.divider} />

      <Text style={styles.sectionLabel}>Test Tone</Text>
      <TextInput
        style={styles.input}
        value={toneFrequencyText}
        onChangeText={setToneFrequencyText}
        keyboardType="decimal-pad"
        accessibilityLabel="Test tone frequency in hertz"
        placeholder="440"
      />
      <Pressable
        onPress={() => playTestTone(1.5)}
        style={styles.button}
        accessibilityRole="button"
        accessibilityLabel="Play reference tone"
        hitSlop={{ top: 14, bottom: 14, left: 14, right: 14 }}
      >
        <Text style={styles.buttonText}>Play Reference Tone</Text>
      </Pressable>
      <Pressable
        onPress={() => playTestTone(0.3)}
        style={styles.button}
        accessibilityRole="button"
        accessibilityLabel="Play confirmation pluck"
        hitSlop={{ top: 14, bottom: 14, left: 14, right: 14 }}
      >
        <Text style={styles.buttonText}>Play Confirmation Pluck</Text>
      </Pressable>
      <Pressable
        onPress={() => Tune2MeAudioEngine.stopTone()}
        style={styles.button}
        accessibilityRole="button"
        accessibilityLabel="Stop tone"
        hitSlop={{ top: 14, bottom: 14, left: 14, right: 14 }}
      >
        <Text style={styles.buttonText}>Stop Tone</Text>
      </Pressable>

      <View style={styles.divider} />

      <Text style={styles.sectionLabel}>Mode 3 Drone Test (simultaneous play + listen)</Text>
      <Pressable
        onPress={toggleDrone}
        style={styles.button}
        accessibilityRole="button"
        accessibilityLabel={isDroneActive ? 'Stop drone' : 'Start drone'}
        hitSlop={{ top: 14, bottom: 14, left: 14, right: 14 }}
      >
        <Text style={styles.buttonText}>{isDroneActive ? 'Stop Drone' : 'Start Drone (Simultaneous)'}</Text>
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    padding: 20,
    paddingTop: 60,
    gap: 12,
    backgroundColor: '#fff',
  },
  title: {
    fontSize: 24,
    fontWeight: '700',
    marginBottom: 8,
  },
  readout: {
    fontSize: 16,
    fontVariant: ['tabular-nums'],
  },
  errorText: {
    fontSize: 15,
    color: '#b00020',
    fontWeight: '600',
  },
  sectionLabel: {
    fontSize: 18,
    fontWeight: '600',
    marginTop: 8,
  },
  divider: {
    height: 1,
    backgroundColor: '#ccc',
    marginVertical: 8,
  },
  input: {
    borderWidth: 1,
    borderColor: '#999',
    borderRadius: 6,
    padding: 10,
    fontSize: 16,
  },
  button: {
    backgroundColor: '#1a4fd6',
    borderRadius: 8,
    paddingVertical: 14,
    paddingHorizontal: 16,
    alignItems: 'center',
    minHeight: 44,
    justifyContent: 'center',
  },
  buttonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
});
