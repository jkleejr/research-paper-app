# App Store submission — Paper Reader

Working notes for the first public App Store release. Version **1.1 (4)**, bundle ID
`com.jklwjr.PaperReader`, team `42WF5JQ74Y`, iPhone only.

---

## 1. Done in the codebase

- **Privacy manifest** — `PaperReader/Resources/PrivacyInfo.xcprivacy` declares no tracking,
  no collected data, and the required reason for `UserDefaults` (`CA92.1`). Verified to land
  in Copy Bundle Resources. Apple rejects submissions that touch required-reason APIs without
  one.
- **Build number** bumped to 4 (build 3 was already uploaded to TestFlight; App Store Connect
  rejects a reused build number).
- **First-run key gate is no longer a hard wall.** It was a non-dismissible sheet, so anyone
  without a key — including an App Review tester — saw an unusable app. It's now dismissible
  ("Not Now"), with a persistent tappable banner on the library screen explaining what the key
  is for.
- **Data disclosure in-app** — the key screen now states plainly that the key lives in the
  Keychain, that paper text is sent to Google, and links the privacy policy. Settings gained an
  About section (version, privacy policy, support) and a **Remove API Key** action, which is the
  in-app data-deletion path reviewers look for.
- **`Support/*.xcconfig` excluded from the target** in `project.yml`. Those files were vestigial
  from the embedded-key era and nothing reads `GEMINI_API_KEY` anymore, but excluding them
  guarantees a key can never ride along in a build. Git history is clean of keys (verified).
- Release build passes: `xcodebuild -scheme PaperReader -configuration Release build`.
- **Screenshot pipeline** — a `PaperReaderUITests` target drives the app and captures every
  screen at full device resolution, with a seeding tool that stages a sample library. Test
  target only; it is not part of the shipped app. See `Tools/screenshots/README.md`.

## 2. Still to do — outside the code

### Host the two pages (required before you can fill in App Store Connect)
`docs/privacy.html` and `docs/index.html` are written and ready. Enable GitHub Pages on the
public `jkleejr/research-paper-app` repo: **Settings → Pages → Source: main branch, /docs
folder**. That produces the URLs already compiled into the app:

- Privacy Policy — `https://jkleejr.github.io/research-paper-app/privacy.html`
- Support — `https://jkleejr.github.io/research-paper-app/`

If you host them anywhere else, update `AppConfig.privacyPolicyURL` / `supportURL` and rebuild.

### Delete the stale key on your Mac
`PaperReader/Support/Secrets.xcconfig` still contains a plaintext Gemini key
(`AQ.Ab8RN6Jf…`). It is gitignored, never was committed, and no longer builds into the app —
but revoke it in Google AI Studio and delete the file. `Secrets.example.xcconfig` is committed
to the public repo (empty value, harmless) and can go too.

### Screenshots — done
Five 1320×2868 (6.9") images are in `screenshots/appstore/`, ready to upload in filename order:

| # | Screen | Caption |
|---|---|---|
| 01 | Library | Turn research papers into audio |
| 02 | Reader, playing | Follow along, sentence by sentence |
| 03 | Voice picker | Eight narration voices |
| 04 | Library + mini player | Pick up exactly where you left off |
| 05 | API key screen | Bring your own API key |

6.9" is the only size App Store Connect requires, since the app is iPhone-only. The whole
pipeline is repeatable — see `Tools/screenshots/README.md`. Raw unframed captures are in
`screenshots/raw/` if you want to recompose or use a different set.

## 3. App Store Connect fields

| Field | Value |
|---|---|
| Name | Paper Reader |
| Subtitle | Listen to research papers |
| Category | Primary: Education · Secondary: Productivity |
| Age rating | 4+ (no objectionable content, no web browsing, no UGC sharing) |
| Price | Free (or your choice — no IAP either way) |
| Support URL | `https://jkleejr.github.io/research-paper-app/` |
| Privacy Policy URL | `https://jkleejr.github.io/research-paper-app/privacy.html` |
| Copyright | 2026 John Lee |

**Keywords** (100 char limit):
`research,paper,pdf,tts,text to speech,listen,audio,academic,study,narrate,science,reader`

**Promotional text**:
> Turn any research paper into clean, listenable audio. Import a PDF, and Paper Reader strips
> the page furniture and citation clutter, then narrates what's left.

**Description**:
> Paper Reader turns research paper PDFs into audio you can actually listen to.
>
> PDFs of academic papers are hostile to text-to-speech: headers, footers, page numbers, inline
> citations, figure captions, and table fragments all get read aloud as noise. Paper Reader uses
> Google's Gemini models to clean the extracted text into a coherent script first, then narrates
> it — so you hear the paper, not the layout.
>
> • Import any text-based PDF from Files or iCloud Drive
> • Follow along with sentence-by-sentence highlighting, or listen with the screen off
> • Background audio, lock screen controls, adjustable playback speed
> • Eight narration voices to choose from
> • Papers, audio, and progress are saved on device, so you can pick up where you left off
> • Processing resumes where it stopped if you close the app mid-paper
>
> BRING YOUR OWN API KEY
>
> Paper Reader has no subscription and no servers. You supply your own free Google Gemini API
> key, and requests go straight from your phone to Google, billed to your own Google account.
> Text cleanup runs on Gemini's free tier; narration uses Gemini's text-to-speech model, which
> requires billing enabled on your Google account (roughly $1–3 of Google usage per full paper).
> Get a key at aistudio.google.com/apikey.
>
> Your key is stored in the iOS Keychain. Papers and audio never leave your device except as
> text sent to Google to be processed. Nothing is collected by the developer.
>
> Note: Paper Reader reads embedded PDF text and does not perform OCR, so image-only scans
> won't work.

### App Privacy ("nutrition label")
Answer **Data Not Collected**. The app has no backend, no analytics, and no SDKs; text sent to
Google is processed under the user's own API key and account, on their behalf, not collected by
you or a partner acting for you. Say exactly that in review notes (below) so it isn't read as an
omission.

### Export compliance
`ITSAppUsesNonExemptEncryption` is already `false` in Info.plist (HTTPS only), so the upload
skips the compliance questionnaire.

## 4. App Review notes — paste this into "Notes"

> Paper Reader converts research paper PDFs into narrated audio using Google's Gemini API.
>
> The app requires the user's own Gemini API key — there is no subscription or developer-run
> server, and all API usage is billed to the user's own Google account. To review full
> functionality, please use this key:
>
>     <PASTE A WORKING KEY WITH BILLING ENABLED HERE>
>
> Enter it on the first-launch screen, or via Settings → Add API Key.
>
> To test: tap +, choose any text-based PDF (a sample paper is attached / available at
> arxiv.org), wait for processing, then tap the paper to open the player. Processing a full
> paper takes a few minutes; a short PDF is faster.
>
> The app can be browsed without a key — the library and settings are fully accessible — but
> importing and narrating papers requires one.
>
> Privacy: the app has no backend and no analytics. PDFs, extracted text, generated audio, and
> playback progress are stored only on device; the API key is stored in the iOS Keychain. Text
> extracted from imported PDFs is sent directly from the device to Google's Gemini API using the
> user's own key. Nothing is collected by the developer, which is why the privacy label is
> "Data Not Collected."
>
> The app does not perform OCR, so image-only scanned PDFs are not supported.

**Generate a dedicated review key** in a Google Cloud project with billing enabled and a low
budget cap, use it only for this, and revoke it after approval. Review may take a few days and
will consume a few dollars of TTS. Attach a short sample PDF in the review attachment field so
the reviewer doesn't have to find one.

## 5. Ship it

```sh
xcodegen generate
xcodebuild -project PaperReader.xcodeproj -scheme PaperReader \
  -destination 'generic/platform=iOS' -configuration Release archive \
  -archivePath build/PaperReader.xcarchive
```

Then open Xcode → Window → Organizer → Distribute App → App Store Connect, or just archive from
Xcode directly (Product → Archive) which is less fuss for signing.

## 6. Known review risks, in order of likelihood

1. **Guideline 2.1 — reviewer can't exercise the app.** The single biggest one, and entirely
   handled by putting a working key in the review notes. Without it, rejection is near certain.
2. **Guideline 4.2 — minimum functionality.** An app gated behind a third-party API key that the
   user must obtain and enable billing on is unusual. The description and support page are
   written to make the value and the arrangement obvious up front. If rejected here, the fallback
   is to make more of the app work without a key (e.g. reading the raw extracted PDF text).
3. **Guideline 3.1.1 — in-app purchase.** Should not apply: the app sells nothing, and users pay
   Google directly for their own API usage rather than buying digital content in-app. If Apple
   raises it, the argument is that this is a bring-your-own-credentials app in the same shape as
   an email or SSH client, not a storefront.
4. **Minor polish, not a rejection risk:** tapping a paper that is still processing or has failed
   opens `RawTextView`, which is still labelled internally as a pipeline debug view and shows raw
   per-page text dumps. Worth replacing with a proper status screen before or shortly after
   launch.
