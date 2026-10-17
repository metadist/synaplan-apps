# CarPlay — Voice Conversations (iOS 26.4+)

Synaplan appears on the CarPlay display as a **voice-based conversational app**: a list with
"New conversation" and the twelve most recent chats, and a voice screen that only shows the state
(connecting, listening, thinking, speaking, muted). Answers are spoken, never shown. Every
conversation is a normal chat and appears in the iPhone chat history right away.

- Release classification: **store-required**. Native Swift, a scene manifest, a new entitlement,
  a new privacy purpose string and an app-local Capacitor plugin. Nothing here ships over the air.
- No change to the `synaplan` submodule and no new backend endpoint.

## Apple requirements

| Requirement | How the app meets it |
|-------------|----------------------|
| Entitlement `com.apple.developer.carplay-voice-based-conversation` (granted manually by Apple) | Granted; every build signs with it — see [Entitlement](#entitlement) |
| Templates: list, alert, voice control; at most three levels | Root list (level 1) → voice control (level 2) → alert |
| Primary modality of voice upon launch | Every action on the root list starts a voice conversation; there is no text input or reading surface |
| Microphone only while the voice control template is visible | `VoiceConversationEngine` starts after the template is shown and stops before it is dismissed |
| No message content on the display | Rows show the AI-generated chat title (3–5 words) and a relative time; the first-message preview is never read. Widget and channel chats (WhatsApp, email, Telegram — titles may contain phone numbers) are not listed |
| Never instruct the driver to use the iPhone | Copy only states the condition ("You're signed out of Synaplan."); `tests/carplay-contract.test.mjs` rejects "sign in to", "open", "settings" and "iPhone" in CarPlay strings |
| All flows possible without the iPhone | CarPlay never triggers a permission prompt (it would appear on the phone). An undetermined microphone or speech permission ends the conversation with one sentence and is requested the next time the app is in the foreground on the iPhone |
| Audio session only while voice is actively used; `playAndRecord`, mode `voiceChat`, no mixing | One engine for the microphone and the reply, so the driver can talk over the answer. Echo cancellation has to be available; otherwise the reply finishes before the microphone opens again. The first 0.8 s of every sentence measure how much of the reply still reaches the microphone, and only speech 12 dB above that leak for 0.4 s interrupts — a strong echo (e.g. speaker next to the microphone) makes the reply play to the end instead of cutting itself off. Released while muted and when the conversation ends |
| Works while the iPhone is locked | Session mirror with `AfterFirstUnlockThisDeviceOnly` — see [Session](#session-while-the-iphone-is-locked) |

The voice control template uses `CPVoiceControlState.actionButtons` (iOS 26.4) and is presented
full screen, so the chat list is not visible while the driver is talking. The screen is the phase
title ("Connecting", "I'm listening", "Thinking", "Answering", "Muted") and the two buttons, mute
and end. The states carry no image: on iOS 27 the full-screen layout gives a custom state image
no height (measured with bitmaps from 24 to 150 pt, SF Symbols and asset-catalog images alike),
so a phase picture there is not visible, and `backgroundImage` is blurred by the system. The
title and the tones below carry the phase. Below iOS 26.4 the CarPlay scene states that iOS 26.4
or later is required.

## Architecture

```
iPhone scene (WebView SPA) ──► app/synaplan-native.js ──► SynaplanCarSession plugin
                                                                 │ serverUrl, language
                                                                 ▼
SecureStorage Keychain items ──(app active)──► CarSessionStore (own Keychain service,
                                                AfterFirstUnlockThisDeviceOnly)
                                                                 │
CarPlay scene ─► CarPlayRootController ─► SynaplanCarClient ─────┴─► Synaplan backend
                         │                     ▲
                         └─► VoiceConversationEngine (live relay, or SpeechInput + SpeechOutput)
```

All files live in `ios/App/App/CarPlay/`:

| File | Responsibility |
|------|----------------|
| `CarPlaySceneDelegate.swift` | `CPTemplateApplicationSceneDelegate`; starts and stops the root controller |
| `CarPlayRootController.swift` | Root list, empty/error states, voice template, alerts |
| `VoiceConversationEngine.swift` | Hands-free loop. Live relay when the server allows it, otherwise listen → send → speak |
| `LiveVoiceCarPlan.swift` | Pure live/fallback decisions, unit-tested in `ios/CarPlayLogic` |
| `PcmPlaybackStream.swift` | Continuous PCM16 playback with resampling, unit-tested in `ios/CarPlayLogic` |
| `LiveVoiceSession.swift` | Relay socket, PCM16 microphone and playback on `VoiceAudioGraph` |
| `SpeechInput.swift` | Microphone capture, on-device `SpeechTranscriber`, server dictation fallback |
| `SpeechOutput.swift` | Sentence-wise TTS with the user's voice, `AVSpeechSynthesizer` fallback, audio cues |
| `SynaplanCarClient.swift` | URLSession client, SSE streaming, single-flight token refresh |
| `CarSessionStore.swift`, `CarSessionPlugin.swift`, `CarSessionContract.swift` | Session mirror and the JS bridge |
| `CarAPIModels.swift`, `SynaplanStreamParser.swift`, `SpokenTextChunker.swift`, `UtteranceEndpointer.swift` | Pure logic, unit-tested in `ios/CarPlayLogic` |
| `CarPlayStrings.swift`, `CarPlay.xcstrings` | Copy in de, en, es, fr, tr, following the language chosen in the SPA |

The CarPlay scene can run without the phone scene: the app may be launched from the car display
alone, so nothing in CarPlay depends on the WebView.

### Backend contract (existing endpoints)

| Call | Use |
|------|-----|
| `GET /api/v1/chats?limit=30&offset=0` | Recent web chats, up to twelve shown; pinned chats (`pinned`, since v5.2.0) first with a pin icon. The server orders by activity only, so a pinned chat appears when it is among the 30 most recent |
| `POST /api/v1/chats` | Created lazily on the first utterance of a new conversation |
| `POST /api/v1/messages/stream` | SSE; `status: data` chunks are spoken, `complete` / `error` / `message` (limit) end the turn |
| `GET /api/v1/tts/stream?text&language&format=mp3` | The user's voice per sentence |
| `POST /api/v1/messages/upload-file` (`purpose=dictation`) | Server speech-to-text fallback |
| `POST /api/v1/auth/refresh` | Access token renewal (refresh token is not rotated) |
| `GET /api/v1/config/runtime` | `speech.speechToTextAvailable` decides whether the server fallback exists |
| `GET /api/v1/voice/live/options` | Whether a live conversation is allowed, consented, and still inside the budget |
| `POST /api/v1/voice/live/sessions` | Starts one live conversation. Body includes `client: carplay`, which forces the relay socket |
| `POST /api/v1/voice/live/sessions/{id}/ticket` | A fresh ticket for the same session after a short network drop |
| `POST /api/v1/voice/live/sessions/{id}/end` | Ends a session the car cannot use |

Every request carries `Synaplan Mobile V<major>.<minor> CarPlay`, so the backend treats it as the
mobile client. `tests/carplay-contract.test.mjs` fails `ci-local` when any of these fields, routes
or the User-Agent pattern change in the pinned submodule.

### Session while the iPhone is locked

The SPA stores its tokens through `@aparajita/capacitor-secure-storage` with
`WhenUnlocked` accessibility, which CarPlay cannot read while the phone is locked. Whenever the
phone scene becomes active or resigns active, `CarSessionStore` copies the scoped
`syn_native_at_<scope>` / `syn_native_rt_<scope>` items into its own Keychain service
`com.synaplan.carplay.session` with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
(never synchronized). The scope is the same djb2 hash of the normalized server URL that the SPA
uses; `ios/CarPlayLogic` pins reference vectors so both sides cannot drift.

- Logout in the app removes the refresh token; the next sync clears the mirror and CarPlay shows
  "signed out".
- A server switch reloads the SPA; the bootstrap pushes the new URL and the mirror drops tokens
  that belonged to the previous server.
- A refresh that the server definitively rejects clears the mirror.

**Deviation from the plan:** the plan proposed a `MOBILE-APP SEAM` in the submodule's
`nativeAuth.ts` that pushes tokens to the plugin. Reading the SecureStorage items directly from
Swift reaches the same result without touching the public submodule, so the submodule pin stays
on the reviewed release.

### Speech

1. **On device first.** `SpeechTranscriber` with `SpeechAnalyzer` (iOS 26+). Language assets are
   requested in the background; until they are installed the server fallback is used.
2. **Server fallback** when on-device recognition is unavailable for the language and the server
   offers speech-to-text. The utterance is recorded as AAC (`m4a`), uploaded, transcribed and
   deleted by the server.
3. If neither is available the conversation ends with "Speech recognition isn't available right
   now".

End of utterance is detected from the input level (−42 dB, 1.4 s of silence after speech, 8 s
without speech, 60 s maximum). Two silent turns in a row end the conversation. While a reply is
spoken the microphone stays open: speech that holds for about half a second stops the reply and
becomes the next turn. A short noise does not. This needs the device echo canceller, which removes
the spoken reply from the microphone. In a car the reply comes from the car speakers, so this has
to be confirmed on a real head unit; without the canceller the app waits out the reply.

Output: the reply is spoken sentence by sentence while it streams. Markdown, links, code blocks,
tables and `[Memory:N]` badges are removed first. The client requests `format=mp3`; OpenAI,
Mistral, xAI and Google honor it. Piper streams `audio/webm`, which AVFoundation cannot play;
[metadist/synaplan#2396](https://github.com/metadist/synaplan/pull/2396) (backend-only) makes
Piper answer an explicit non-WebM format with WAV. Until a server runs that change, any
unplayable response falls back to the system voice (`AVSpeechSynthesizer`) for the rest of the
conversation.

### Live conversation

When live voice is available, the driver has allowed it, and the monthly budget is not used up,
the car opens the relay socket instead of the turn-based loop. The microphone is PCM16 into the
gateway and the provider audio plays on the same graph. A GPT live voice is 24 kHz. Those packets
are one continuous stream, resampled to the car rate the same way as on the website, so a packet
boundary does not click. Echo cancellation stays on. The voice
model handles talking over a reply. The title uses the same moments as the phone: "I'm
listening" until reply audio arrives, "Thinking" only while Synaplan is working, "Answering"
while that audio is still playing, and "I'm listening" again once the reply has finished. The
relay sends no separate listening or speaking mark, so the car reads them from the audio.
CarPlay has no WebRTC stack, so the server forces `relay`
for `client: carplay` even when the admin switch is on.

The same short tones as a live call on the phone mark the moments the driver cannot see.
A rising pair opens the call, a second rising pair means the line is ready, a short sweep
means the question went to Synaplan, a falling pair is hang-up, and a lower falling pair is
a failure. Speaking, and listening again after an answer, stay silent. The tones play through
the voice engine, and the ready tone finishes before the microphone opens, so echo
cancellation hears them and they are not the first thing the relay transcribes. A reconnect
inside the same call does not play the opening tone again. Reduce Motion does not mute them:
in the car the tone is the signal. The turn-based fallback uses the same melodies, including
one ready tone before each listen. A busy or down live service does not play a closing tone;
the conversation continues.

A used-up budget is one falling tone, then one spoken sentence, and the conversation ends.
The turn-based loop uses the same budget, so it is not offered. A busy or down live service
is one spoken sentence, then the turn-based loop continues in the same chat. Missing consent
stays on that loop without a sentence. The car screen still shows no message text.

A dropped socket keeps the provider session for 20 seconds. The app asks for a new ticket on the
same session id and reconnects. After 20 seconds the server ends it with `network_lost` and the
app says so. A web tab that closes still ends immediately.

Echo and barge-in on a real head unit are still a release gate. This path was not walked on a
device.

### Face ID app lock

The app lock does not apply in CarPlay, matching Claude and ChatGPT. CarPlay shows no message
content, and the driver cannot authenticate while driving.

## Entitlement

Apple granted **Voice-based conversational app** to the team (requested at
[developer.apple.com/carplay](https://developer.apple.com/carplay/)). The grant is a managed
capability of the team, not of a single app:

1. The capability is enabled on the App IDs `com.synaplan.app` and `com.synaplan.app.dev`
   (Certificates, Identifiers & Profiles → Identifiers). A new App ID needs it enabled before its
   first device build.
2. `ios/App/App/App.entitlements` carries the key for Debug and Release, device and Simulator
   alike. `tests/native-manifests.test.mjs` rejects an SDK-conditional override.
3. Enabling a capability invalidates the existing provisioning profiles. The App Store
   distribution profile was regenerated and stored in the `IOS_PROVISIONING_PROFILE_BASE64`
   secret of the `store-qa` environment ([`STORE_SETUP.md`](STORE_SETUP.md)); development profiles come
   from Xcode automatic signing. A profile without the key fails the export with a missing
   entitlement error.

## Testing

| Layer | Command | Where |
|-------|---------|-------|
| Contract, manifests, strings, bootstrap | `npm run ci-local` | Any OS (CI) |
| Pure Swift logic (SSE parser, chunker, endpointer, scope hash, decoding, live route) | `npm run test:carplay` | macOS only |
| CarPlay journey | Manual, see below | Real iPhone + CarPlay Simulator, or Xcode 26.4 Simulator |

### Where CarPlay can run

**Not in the Xcode 27 simulator.** Xcode 27 replaced the Simulator app with Device Hub, which has
no "I/O > External Displays > CarPlay" menu
([Apple Developer Forums](https://developer.apple.com/forums/thread/834440)). The capability is
also gone underneath: external simulator screens render no pixels under Xcode 27 and the simulator
runtime cannot start a CarPlay session (investigation on Xcode 27.0 and 27.1 beta in
[baguette's companion-screens design notes](https://github.com/tddworks/baguette/blob/main/docs/features/companion-screens/design.md)).

| Environment | What it covers | Needs |
|-------------|----------------|-------|
| Real iPhone (iOS 27) + **CarPlay Simulator** (Device Hub / Additional Tools for Xcode) | Everything, including the full-screen voice screen and the lock test | The granted entitlement in a development profile |
| **Xcode 26.4** side by side, Simulator app, iOS 26.4 runtime | List, full-screen voice template, alerts, lock test | Xcode 26.4 download (Apple ID) |
| Real car or wireless head unit | Echo cancellation, radio interruption | The granted entitlement |

The phone side (session mirror, bootstrap bridge, permission hand-off) runs in any simulator.

### Journey

1. Start the backend (`localhost:8000`), then
   `SYNAPLAN_ENV=dev SYNAPLAN_API_BASE_URL=http://localhost:8000 ./build.sh` and run the app in one
   of the environments above. In the Xcode 26.4 Simulator, open I/O > External Displays > CarPlay.
2. Walk:
   1. Signed out: CarPlay shows "Not signed in" with one sentence and no list.
   2. Sign in on the iPhone (`demo@synaplan.com` / `demo123` locally): the list shows "New
      conversation" and recent chats with relative times; no WhatsApp, email or widget chats.
   3. With the microphone permission still undetermined (`xcrun simctl privacy <UDID> reset
      microphone <bundle id>`): the conversation ends with "Synaplan doesn't have access to the
      microphone." and no dialog appears on the phone; the next time the app is opened on the
      phone, the system asks.
   4. New conversation fills the screen (the chat list is gone). A short rising tone, then
      "Connecting" → a second rising tone when the line is ready → listening → a short
      sweep when the question is sent → speaking, with no extra tone under the answer. The
      title is "I'm listening" while the driver talks, "Thinking" only during a lookup,
      "Answering" while the reply plays, and "I'm listening" again once it has finished.
      End plays a falling tone. On a real head
      unit, those tones must not show up in the chat transcript.
   5. Mute: other audio may resume. Unmute; End. The list reloads and the chat appears at the top
      and in the iPhone history.
   6. Continue an existing chat.
   7. Lock the simulator (Cmd+L) and repeat — this proves the session mirror.
   8. Quit the app and launch it from the CarPlay display only.
   9. Stop the backend: "Synaplan can't be reached" with a retry row.
   10. Switch the SPA language to English and German with CarPlay connected; the next
       conversation listens, answers, and speaks in the new language without leaving the app
       (the bootstrap pushes every `<html lang>` change, including the account language applied
       after sign-in).

Screenshots in the Xcode 26.4 Simulator: `xcrun simctl io <device> screenshot --display=external
out.png`.

## App Review notes

- Category: voice-based conversational app. The CarPlay surface lists chats by title and speaks
  answers; no answer text is ever displayed.
- Provide the demo account; the reviewer signs in on the iPhone once, then uses CarPlay.
- The microphone is active only while the voice screen is visible.
- Speech is recognized on the iPhone; when that is not possible, the recorded utterance is sent to
  the user's Synaplan server for transcription and deleted afterwards.
