---
epic: 7
title: Native Device Features & Lifecycle
sprint: "Sprint 7"
aspect: null
status: planned
depends_on: [3]
repos:
  - synaplan-apps (private)
  - synaplan (public, submodule)
estimate: M
---

# Epic 7 — Native Device Features & Lifecycle

> The SPA uses capabilities that need native bridges + permissions inside a WebView. This epic
> also hardens the auth/session lifecycle proven in Epic 3 (secure storage, resume-reconnect) and
> provides the concrete "native value" that defeats Apple Guideline 4.2 (detailed in Epic 9).

## Goal

File upload, microphone, download/share, secure token storage, and robust app-lifecycle handling
all work natively, with correct permission prompts and graceful offline behavior.

## v4.0 context / Why

These are the differences between "a website in a shell" (rejected) and "an app". They also make
the app actually usable for Synaplan's core flows (RAG uploads, voice, generated-file sharing).

## Scope

### In scope

- Camera / file picker / microphone with permissions + usage strings.
- File download / preview / share.
- Secure storage (Keychain / Keystore) for the auth token; optional biometric lock.
- App-lifecycle: resume-reconnect (WS/Centrifugo), session re-check, SSE recovery, token refresh.
- Network/offline handling; reCAPTCHA + CSP under the `capacitor://` origin.
- Guest mode + device-locale mapping (de/en/es/tr).

### Out of scope (deferred)

- Push notifications → explicitly v2 (keep architecture open, don't build).

## Tasks

### 7.1 — Media & files

- [ ] `@capacitor/camera` + photo/file picker for RAG document/image upload; cross-origin upload
      with the Bearer token (Epic 3). Add iOS `NSCameraUsageDescription` / Android manifest perms.
- [ ] Microphone for voice/whisper.cpp: mic permission (`NSMicrophoneUsageDescription`), native
      audio if needed.
- [ ] Download/preview generated images + PDFs via `@capacitor/share` + Filesystem.
- [ ] Every permission needs a **purpose string** (iOS Info.plist / Android manifest) — missing
      ones cause **crash/reject**.

### 7.2 — Secure storage & lifecycle (hardens Epic 3)

- [ ] Store the auth token in iOS **Keychain** / Android **Keystore / EncryptedSharedPreferences**
      (secure-storage plugin), **not** plain `@capacitor/preferences`. Optional biometric lock.
- [ ] On **resume from background**: reconnect WebSocket/Centrifugo, re-check session validity,
      recover aborted SSE streams; long-run token refresh + rotation.

### 7.3 — Network, CSP, reCAPTCHA, locale

- [ ] `@capacitor/network` + sensible offline UI (the current service worker caches nothing).
- [ ] reCAPTCHA (login/register, from runtime config) can break under `capacitor://` — domain
      allow-list or a native path; adjust the `index.html` CSP for the `capacitor://` scheme
      (coordinate with Epic 1's CSP change). WKWebView config (`allowsInlineMediaPlayback`,
      cleartext for local testing only).
- [ ] Decide whether **guest sessions** make sense in the app; map device locale → de/en/es/tr.

## Acceptance criteria (Definition of Done)

- Upload a document and an image from camera + file picker; record voice; download + share a
  generated file — all on a real device, with correct permission prompts.
- Denying a permission degrades gracefully (no crash).
- Token is in encrypted native storage; backgrounding + resuming restores realtime + session.
- Offline shows a sensible state and recovers on reconnect.
- reCAPTCHA works (or a native equivalent) in the app; no white screen from CSP.

## Test notes (for the QA person)

- Camera/file upload, mic, download/share; **permission denial** paths.
- Background the app for several minutes → resume → realtime + chat still work (Epic 3 overlap).
- Airplane mode on/off mid-session → offline UI → reconnect.
- Locale mapping on a device set to each of de/en/es/tr.

## Risks & mitigations

- **Missing iOS purpose strings → hard reject/crash:** audit Info.plist before any submission.
- **reCAPTCHA breaking under capacitor origin:** allow-list/native path; test in release build.
- **Token in insecure storage:** enforce Keychain/Keystore, never preferences/localStorage.

## Open questions

- Is guest mode in-scope for the app at launch?
- Biometric lock at launch or v2?
