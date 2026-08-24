import type { CapacitorConfig } from "@capacitor/cli";

const config: CapacitorConfig = {
  appId: "com.bao.homeos",
  appName: "Home OS",
  webDir: "www",
  server: {
    // The native shell loads the Render site so web fixes can be released
    // without rebuilding the container. The version manifest remains the
    // source of truth for the in-app update check.
    url: "https://life-manager-1.onrender.com/",
    cleartext: false,
    allowNavigation: ["life-manager-1.onrender.com"],
  },
  ios: {
    contentInset: "automatic",
  },
};

export default config;
