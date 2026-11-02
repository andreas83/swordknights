import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.swordknights.game',
  appName: 'Swordknights',
  webDir: 'dist',
  android: {
    backgroundColor: '#2B0A14',
  },
  ios: {
    backgroundColor: '#2B0A14',
    contentInset: 'never',
  },
};

export default config;
