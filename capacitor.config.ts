import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import type { CapacitorConfig } from '@capacitor/cli'

// Identifiers are locked in docs/IDENTIFIERS.md.
// NOTE: per-environment bundle IDs (com.synaplan.app[.dev|.staging]) are wired in Epic 10
// via build-time config; this file holds the production defaults.

// ── Aspect 1: client identity (Epic 2) ───────────────────────────────────────
// Single source of truth for the version = this repo's package.json. The UA token is
// derived here at config-eval time (cap sync / build), so bumping the app version updates
// the UA automatically. Format is FROZEN in docs/IDENTIFIERS.md and parsed by the backend:
//   Synaplan Mobile V<major>.<minor>   (e.g. "Synaplan Mobile V4.0")
// NOTE: the Capacitor CLI loads this file as CommonJS (require), so `import.meta` is not
// available — read package.json relative to the project root (cwd), where the CLI runs.
const pkg = JSON.parse(readFileSync(join(process.cwd(), 'package.json'), 'utf-8')) as {
  version: string
}
const [major, minor] = pkg.version.split('.')
const appUserAgent = `Synaplan Mobile V${major}.${minor}`

// ── Dev-only: point the app at a local backend for the Epic 3 spike ───────────
// When SYNAPLAN_DEV_BACKEND is set at `cap sync` time (e.g. http://10.0.2.2:8000
// for the Android emulator's host loopback), we relax the WebView so the bundled
// https://localhost SPA may reach a cleartext local backend cross-origin. This
// is OFF by default — production stays strict (no cleartext, no mixed content).
const devBackendUrl = process.env.SYNAPLAN_DEV_BACKEND?.trim()

const config: CapacitorConfig = {
  appId: 'com.synaplan.app',
  appName: 'Synaplan',
  // Appended (not overridden) to the default WKWebView/Android WebView UA so the token
  // rides on ALL WebView transports — fetch/XHR, EventSource/SSE, and the WebSocket
  // upgrade — which JS-set headers cannot do. Backend detection: Epic 2.2.
  appendUserAgent: appUserAgent,
  // The bundled SPA produced by ./build.sh. No remote server.url in production —
  // the app loads the bundled dist/ from the local origin (capacitor://localhost).
  webDir: 'synaplan/frontend/dist',
  // iosScheme is revisited in Epic 3 (cookie/origin parity). Default 'capacitor' for now;
  // native auth uses Bearer tokens (Epic 3), so cross-origin cookie parity is not required.
  ios: {
    contentInset: 'always',
  },
  android: {
    // Allow http only for local dev tooling; production talks to https. Hardened in Epic 7.
    allowMixedContent: Boolean(devBackendUrl),
  },
  // Dev spike only: allow cleartext so the emulator can reach the local backend.
  ...(devBackendUrl ? { server: { cleartext: true } } : {}),
  plugins: {
    SplashScreen: {
      launchShowDuration: 1500,
      launchAutoHide: true,
      backgroundColor: '#003fc7',
      androidScaleType: 'CENTER_CROP',
      showSpinner: false,
      splashFullScreen: true,
      splashImmersive: false,
    },
    Keyboard: {
      // Non-Ionic Vue SPA: let the WebView resize natively so the chat input stays visible.
      resize: 'native',
      resizeOnFullScreen: true,
    },
    // ── OTA live updates (Epic 8.1, Capgo) ─────────────────────────────────────
    // Ships CONFORMING web-asset fixes without a store review. Behavior/payment
    // logic must NEVER be OTA'd — see docs/OTA_POLICY.md.
    //
    // Code-first: this block is inert until the app is registered with the update
    // server and a bundle is published (no bundle ⇒ the builtin dist/ is used).
    // Hosting for v4.0 = Capgo Cloud (default updateUrl); migrating to a
    // self-hosted server later is just an updateUrl/channelUrl override here —
    // no app code change.
    CapacitorUpdater: {
      // Chosen behavior: download in the background, apply on the next cold start.
      autoUpdate: true,
      // On a native store update, discard any OTA bundle and fall back to the
      // freshly shipped builtin bundle so an old OTA bundle never shadows new
      // native code.
      resetWhenUpdate: true,
      // Apply downloaded bundles on the next app start, not mid-session.
      directUpdate: false,
      // Safety: if a freshly applied bundle does not call notifyAppReady() within
      // this window, Capgo auto-reverts to the previous good bundle.
      appReadyTimeout: 10000,
      autoDeleteFailed: true,
      autoDeletePrevious: true,
      // Signature / E2E encryption (enabled per decision): run
      // `npm run ota:key:create` to inject `publicKey` here and keep the private
      // key as a release secret (docs/SECRETS.md). Bundles are then verified on
      // device and rejected if tampered.
    },
  },
}

export default config
