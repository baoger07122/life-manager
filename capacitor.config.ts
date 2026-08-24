import type { CapacitorConfig } from "@capacitor/cli";

const config: CapacitorConfig = {
  appId: "com.bao.homeos",
  appName: "Home OS",
  webDir: "www",
  server: {
    // Start from the bundled local boot page, then navigate to Render after
    // the remote application has loaded. This avoids a blank launch screen.
    cleartext: false,
    allowNavigation: ["life-manager-1.onrender.com"],
  },
  ios: {
    contentInset: "automatic",
  },
};

export default config;
