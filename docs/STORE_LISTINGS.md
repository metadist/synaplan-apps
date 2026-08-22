# Store Listings — Metadata & Copy (Epic 10.4)

> Launch copy for **App Store Connect** and **Google Play**, in the four launch locales
> **en / de / es / tr**. This is the text source of truth; in Epic 10.5 it drops into the
> fastlane `metadata/` (deliver) and `metadata/android/` (supply) trees. Screenshots, the age
> rating questionnaire, and final URLs are **device/account-gated** (👤 below).

## Store-safety rules applied here

- **No third-party trademarks** in the app name, subtitle, or keywords (e.g. no "ChatGPT",
  "Claude", "Gemini", "GPT" as keywords — Apple/Google reject competitor/owned marks). We say
  "leading AI models" generically. The provider names may appear in the long description as a
  factual feature statement only.
- **No anti-steering violations:** the listing does not advertise cheaper web prices or link to
  a web checkout for the subscription (Epic 5/9). Pricing is shown via the store products.
- **Honest minimum-functionality framing** (Guideline 4.2): copy leads with the native value
  (chat, your documents, voice, images, offline-aware), not "a website in an app".
- Self-hosters re-brand the listing for their own store account; this file is the **Synaplan
  SaaS** default that the `web.synaplan.com` build ships against.

## Field length limits (count before submitting)

| Field | App Store | Google Play |
|-------|-----------|-------------|
| App name / title | ≤ 30 | ≤ 30 |
| Subtitle (iOS) / Short description (Play) | ≤ 30 | ≤ 80 |
| Promotional text (iOS, updatable w/o review) | ≤ 170 | — |
| Keywords (iOS, comma-separated) | ≤ 100 | — (Play has no keyword field) |
| Description / Full description | ≤ 4000 | ≤ 4000 |
| What's New / release notes | ≤ 4000 | ≤ 500 |

## Shared decisions (👤 confirm before submission)

- **Primary category:** Productivity. **Secondary (iOS):** Utilities or Business.
- **Age rating:** 👤 An AI chat app with open user input typically lands at **iOS 17+ /
  Play "Teen"** unless content is moderated — confirm via each store's questionnaire. Do not
  guess; the rating must match actual behavior.
- **URLs** (default to the Epic 4 branding / Epic 9 legal links; self-hosters override):
  - Marketing/website: `https://www.synaplan.com`
  - Support: 👤 `https://www.synaplan.com/support` or a support email — confirm.
  - Privacy Policy: 👤 confirm canonical URL (Epic 9.3).
  - Terms of Use (Play "Terms"/iOS EULA): 👤 confirm.
- **Account-deletion URL** (Google requires it in the listing): the public deletion page from
  Epic 9.1 — 👤 confirm final URL.

---

# Apple App Store

## English (en) — primary

- **App name (≤30):** `Synaplan: AI Chat & Knowledge` (29)
- **Subtitle (≤30):** `Chat with AI and your files` (27)
- **Promotional text (≤170):** Chat with leading AI models and your own documents in one private
  assistant. Bring your files, ask in your words, get answers with sources. Works on any Synaplan
  server.
- **Keywords (≤100):** `ai,chat,assistant,knowledge,documents,rag,notes,voice,images,productivity,search,files`
- **Description (≤4000):**

```
Synaplan is your private AI assistant that talks to leading AI models AND your own knowledge.

Ask questions in plain language and get answers grounded in your own documents, not just the
model's training data. Upload files into knowledge folders and chat with them — reports,
manuals, notes, research — and get answers with the sources they came from.

WHY SYNAPLAN
• One assistant, many models — pick the AI that fits the task.
• Chat with your documents (RAG): upload files and ask across them.
• Voice input: dictate instead of typing.
• Image generation: create visuals right in the chat.
• Tools & knowledge folders to organize how you work.
• Private by design: your data flows through the server you choose.

BUILT FOR YOU
• Connect to Synaplan.com or to your own self-hosted Synaplan server — you decide where your
  data lives.
• Clean, fast, native experience: dark mode, offline-aware, share and save results.
• Available in English, German, Spanish, and Turkish.

SUBSCRIPTIONS
Free to start. Optional subscriptions unlock higher usage and advanced features, billed through
your App Store account. Manage or cancel anytime in your account settings.

Synaplan is flexible and open: the platform is brandable and can be self-hosted, so the same app
works for Synaplan.com and for your own AI platform.
```

- **What's New (≤4000):** `First v4.0 release: native iOS app — chat with leading AI models and your own documents, voice input, image generation, dark mode, and per-server sign-in.`

## German (de)

- **App name (≤30):** `Synaplan: KI-Chat & Wissen` (26)
- **Subtitle (≤30):** `KI-Chat mit deinem Wissen` (25)
- **Promotional text (≤170):** Chatte mit führenden KI-Modellen und deinen eigenen Dokumenten in
  einem privaten Assistenten. Lade Dateien hoch, frag in eigenen Worten, erhalte Antworten mit
  Quellen.
- **Keywords (≤100):** `ki,chat,assistent,wissen,dokumente,rag,notizen,sprache,bilder,produktiv,suche,dateien`
- **Description (≤4000):**

```
Synaplan ist dein privater KI-Assistent, der mit führenden KI-Modellen UND deinem eigenen Wissen
spricht.

Stelle Fragen in normaler Sprache und erhalte Antworten, die auf deinen eigenen Dokumenten
beruhen – nicht nur auf dem Trainingswissen des Modells. Lade Dateien in Wissensordner und
chatte mit ihnen: Berichte, Handbücher, Notizen, Recherchen – inklusive der Quellen.

WARUM SYNAPLAN
• Ein Assistent, viele Modelle – wähle die KI, die zur Aufgabe passt.
• Chatte mit deinen Dokumenten (RAG): Dateien hochladen und übergreifend fragen.
• Spracheingabe: diktieren statt tippen.
• Bildgenerierung: Visuals direkt im Chat erstellen.
• Tools & Wissensordner für deine Arbeitsweise.
• Privat by Design: deine Daten laufen über den Server deiner Wahl.

FÜR DICH GEMACHT
• Verbinde dich mit Synaplan.com oder deinem eigenen, selbst gehosteten Synaplan-Server – du
  entscheidest, wo deine Daten liegen.
• Klar, schnell, nativ: Dark Mode, Offline-Hinweise, Ergebnisse teilen und speichern.
• Verfügbar auf Deutsch, Englisch, Spanisch und Türkisch.

ABOS
Kostenlos starten. Optionale Abos schalten mehr Nutzung und erweiterte Funktionen frei,
abgerechnet über dein App-Store-Konto. Jederzeit in den Kontoeinstellungen verwalten oder
kündigen.

Synaplan ist flexibel und offen: Die Plattform ist brandbar und selbst hostbar – dieselbe App
funktioniert für Synaplan.com und für deine eigene KI-Plattform.
```

- **What's New (≤4000):** `Erstes v4.0-Release: native iOS-App – chatte mit führenden KI-Modellen und deinen eigenen Dokumenten, Spracheingabe, Bildgenerierung, Dark Mode und Anmeldung pro Server.`

## Spanish (es)

- **App name (≤30):** `Synaplan: IA y Conocimiento` (27)
- **Subtitle (≤30):** `Chatea con IA y tus archivos` (28)
- **Promotional text (≤170):** Chatea con los mejores modelos de IA y tus propios documentos en un
  asistente privado. Sube archivos, pregunta a tu manera y recibe respuestas con sus fuentes.
- **Keywords (≤100):** `ia,chat,asistente,conocimiento,documentos,rag,notas,voz,imagenes,productividad,buscar,archivos`
- **Description (≤4000):**

```
Synaplan es tu asistente de IA privado que habla con los mejores modelos de IA Y con tu propio
conocimiento.

Haz preguntas en lenguaje natural y obtén respuestas basadas en tus propios documentos, no solo
en lo que el modelo aprendió. Sube archivos a carpetas de conocimiento y chatea con ellos:
informes, manuales, notas, investigaciones, con sus fuentes.

POR QUÉ SYNAPLAN
• Un asistente, muchos modelos: elige la IA adecuada para cada tarea.
• Chatea con tus documentos (RAG): sube archivos y pregunta sobre todos ellos.
• Entrada por voz: dicta en lugar de escribir.
• Generación de imágenes: crea visuales dentro del chat.
• Herramientas y carpetas de conocimiento para tu forma de trabajar.
• Privado por diseño: tus datos pasan por el servidor que elijas.

HECHO PARA TI
• Conéctate a Synaplan.com o a tu propio servidor Synaplan autoalojado: tú decides dónde están
  tus datos.
• Experiencia nativa, clara y rápida: modo oscuro, aviso sin conexión, compartir y guardar
  resultados.
• Disponible en español, inglés, alemán y turco.

SUSCRIPCIONES
Empieza gratis. Las suscripciones opcionales desbloquean más uso y funciones avanzadas, con cargo
a tu cuenta de App Store. Gestiona o cancela cuando quieras en los ajustes de tu cuenta.

Synaplan es flexible y abierto: la plataforma es personalizable y autoalojable, así que la misma
app sirve para Synaplan.com y para tu propia plataforma de IA.
```

- **What's New (≤4000):** `Primera versión v4.0: app nativa para iOS: chatea con los mejores modelos de IA y tus propios documentos, entrada por voz, generación de imágenes, modo oscuro e inicio de sesión por servidor.`

## Turkish (tr)

- **App name (≤30):** `Synaplan: YZ Sohbet & Bilgi` (27)
- **Subtitle (≤30):** `YZ ve bilgilerinle sohbet` (25)
- **Promotional text (≤170):** Önde gelen yapay zeka modelleri ve kendi belgelerinle tek bir özel
  asistanda sohbet et. Dosyalarını yükle, kendi sözlerinle sor, kaynaklarıyla yanıt al.
- **Keywords (≤100):** `yapay zeka,yz,sohbet,asistan,bilgi,belge,rag,notlar,ses,görsel,verimlilik,arama,dosya`
- **Description (≤4000):**

```
Synaplan; önde gelen yapay zeka modelleriyle VE kendi bilginle konuşan özel yapay zeka asistanın.

Soruları günlük dille sor ve yalnızca modelin eğitildiği bilgilere değil, kendi belgelerine
dayanan yanıtlar al. Dosyaları bilgi klasörlerine yükle ve onlarla sohbet et: raporlar,
kılavuzlar, notlar, araştırmalar — kaynaklarıyla birlikte.

NEDEN SYNAPLAN
• Tek asistan, çok model — göreve uygun yapay zekayı seç.
• Belgelerinle sohbet (RAG): dosya yükle ve hepsine birden sor.
• Sesli giriş: yazmak yerine dikte et.
• Görsel üretimi: doğrudan sohbette görsel oluştur.
• Çalışma şekline uygun araçlar ve bilgi klasörleri.
• Tasarımı gereği özel: verilerin senin seçtiğin sunucudan geçer.

SENİN İÇİN
• Synaplan.com'a ya da kendi barındırdığın Synaplan sunucusuna bağlan — verilerinin nerede
  olacağına sen karar ver.
• Sade, hızlı, yerel deneyim: koyu mod, çevrimdışı bildirimi, sonuçları paylaş ve kaydet.
• Türkçe, İngilizce, Almanca ve İspanyolca mevcut.

ABONELİKLER
Ücretsiz başla. İsteğe bağlı abonelikler daha fazla kullanım ve gelişmiş özellikler açar; App
Store hesabın üzerinden faturalandırılır. İstediğin zaman hesap ayarlarından yönet veya iptal et.

Synaplan esnek ve açıktır: platform markalanabilir ve kendi sunucunda barındırılabilir; aynı
uygulama hem Synaplan.com hem de kendi yapay zeka platformun için çalışır.
```

- **What's New (≤4000):** `İlk v4.0 sürümü: yerel iOS uygulaması — önde gelen yapay zeka modelleri ve kendi belgelerinle sohbet, sesli giriş, görsel üretimi, koyu mod ve sunucu bazlı oturum açma.`

---

# Google Play

> Play has no keyword field (the full description is indexed). Title ≤30, short description ≤80,
> full description ≤4000, release notes ≤500.

## English (en)

- **Title (≤30):** `Synaplan: AI Chat & Knowledge` (29)
- **Short description (≤80):** `Chat with leading AI models and your own documents — private, on any server.` (76)
- **Full description (≤4000):** same body as the App Store English description above.
- **Release notes (≤500):** `First v4.0 release: chat with leading AI models and your own documents, voice input, image generation, dark mode, and per-server sign-in.`

## German (de)

- **Title (≤30):** `Synaplan: KI-Chat & Wissen` (26)
- **Short description (≤80):** `Chatte mit Top-KI-Modellen und deinen Dokumenten – privat, auf jedem Server.` (76)
- **Full description (≤4000):** wie die deutsche App-Store-Beschreibung oben.
- **Release notes (≤500):** `Erstes v4.0-Release: chatte mit führenden KI-Modellen und deinen Dokumenten, Spracheingabe, Bildgenerierung, Dark Mode und Anmeldung pro Server.`

## Spanish (es)

- **Title (≤30):** `Synaplan: IA y Conocimiento` (27)
- **Short description (≤80):** `Chatea con los mejores modelos de IA y tus documentos, en tu servidor.` (70)
- **Full description (≤4000):** como la descripción de App Store en español, arriba.
- **Release notes (≤500):** `Primera versión v4.0: chatea con los mejores modelos de IA y tus documentos, entrada por voz, generación de imágenes, modo oscuro e inicio de sesión por servidor.`

## Turkish (tr)

- **Title (≤30):** `Synaplan: YZ Sohbet & Bilgi` (27)
- **Short description (≤80):** `Önde gelen YZ modelleri ve kendi belgelerinle sohbet — özel, her sunucuda.` (73)
- **Full description (≤4000):** yukarıdaki Türkçe App Store açıklamasıyla aynı.
- **Release notes (≤500):** `İlk v4.0 sürümü: önde gelen YZ modelleri ve kendi belgelerinle sohbet, sesli giriş, görsel üretimi, koyu mod ve sunucu bazlı oturum açma.`

---

## Screenshots (Epic 6 assets × this copy) — 👤 still to produce

Required sets (per launch locale where text appears in-image; otherwise reuse en):

- **iOS:** 6.9" (iPhone 16 Pro Max) and 6.5" required; 13" iPad if iPad is supported (👤 decide).
- **Android:** phone (min 2), 7" + 10" tablet if tablet supported; plus a 1024×500 feature graphic.

Suggested caption flow (keep ≤ ~6 words each, localized): 1) "Chat with leading AI models" ·
2) "Answers from YOUR documents" · 3) "Speak instead of type" · 4) "Generate images in chat" ·
5) "Your data, your server".
