import { StatusBar } from 'expo-status-bar';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import AudioEngineDebugScreen from './src/screens/AudioEngineDebugScreen';

// Phase 1 of the build plan: prove the native audio engine works on real
// hardware before any real app screens/navigation exist. This IS the app,
// for now.
export default function App() {
  return (
    <SafeAreaProvider>
      <AudioEngineDebugScreen />
      <StatusBar style="auto" />
    </SafeAreaProvider>
  );
}
