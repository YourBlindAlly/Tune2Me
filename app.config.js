const isPreview = process.env.APP_VARIANT === 'preview';

module.exports = {
  expo: {
    name: isPreview ? 'Tune2Me (Preview)' : 'Tune2Me',
    slug: 'tune2me-app',
    version: '1.0.0',
    orientation: 'portrait',
    icon: './assets/icon.png',
    userInterfaceStyle: 'light',
    ios: {
      supportsTablet: true,
      bundleIdentifier: isPreview ? 'com.rustyperez.tune2me.preview' : 'com.rustyperez.tune2me',
      buildNumber: process.env.BUILD_NUMBER || '1',
      infoPlist: {
        NSMicrophoneUsageDescription:
          'Tune2Me listens through the microphone to detect the pitch you play, so it can tell you how close you are to being in tune.',
        UIBackgroundModes: ['audio'],
        ITSAppUsesNonExemptEncryption: false,
      },
    },
    android: {
      adaptiveIcon: {
        backgroundColor: '#E6F4FE',
        foregroundImage: './assets/android-icon-foreground.png',
        backgroundImage: './assets/android-icon-background.png',
        monochromeImage: './assets/android-icon-monochrome.png',
      },
      predictiveBackGestureEnabled: false,
    },
    web: {
      favicon: './assets/favicon.png',
    },
  },
};
