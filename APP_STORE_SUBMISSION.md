# App Store submission — Paper Reader

Working notes for the first public App Store release. Version **1.0 (4)**, bundle ID
`com.jklwjr.PaperReader`, team `42WF5JQ74Y`, iPhone only.

> **Submitted for review 2026-08-17** — 1.0 (4), awaiting Apple. What went in, where it
> differs from the plan below: App Store name kept as **"Paper Reader App"**; category
> **Productivity** primary, **Education** secondary (the reverse of the recommendation);
> screenshots uploaded at **6.5" (1242×2688)**, the only iPhone size this record offers;
> DSA trader status declared **non-trader**; Content Rights answered yes-with-rights, on the
> strength of the CC BY 4.0 sample; privacy label **Data Not Collected**, published; age
> rating 4+; review notes pasted **without** a demo key.
>
> Still outstanding: run 1.0 (4) on a real iPhone —
> it is on TestFlight now, so installing from there tests the exact submitted binary. If that
> turns up a problem, the version can be pulled with **Remove from Review**, fixed, and
> resubmitted as build 5.

---

## 1. Done in the codebase

- **Privacy manifest** — `PaperReader/Resources/PrivacyInfo.xcprivacy` declares no tracking,
  no collected data, and the required reason for `UserDefaults` (`CA92.1`). Verified to land
  in Copy Bundle Resources. Apple rejects submissions that touch required-reason APIs without
  one.
- **Version 1.0, build 4.** 1.0 matches the version record already waiting in App Store Connect
  — a build only appears under a record whose number matches its `CFBundleShortVersionString`,
  so these have to agree. Build 4 because 3 went to TestFlight and a build number can't be
  reused. If you upload and then need any change, bump `CFBundleVersion` and re-run
  `xcodegen generate`.
- **A bundled sample paper, playable with no key at all.** `SampleLibrary` installs it on first
  launch: a real CC BY 4.0 paper, cleaned and narrated once by a developer (`Tools/sample/`) and
  shipped as audio. Every chunk is pre-cached and plays from the app bundle, so it makes no API
  calls, costs users nothing however many download it, and puts no key in the binary. This is
  what lets a reviewer — or anyone — see the whole app work before getting a key.
- **The first-run key gate is gone.** It used to be a non-dismissible sheet, so anyone without a
  key saw an unusable app. The library now opens with the sample ready to play, and the key is
  asked for at the moment it's first needed: tapping **+** to import your own PDF. Saving a key
  there continues straight on to the file picker rather than dead-ending.
- **`TextRepair` rebuilds words in PDFs that extract without spaces.** Some publishers justify
  text by positioning glyphs instead of emitting spaces, so PDFKit returns whole lines run
  together ("examinedbyeconomistswhogenerallydonot"); every PDFKit route returns the same string.
  Segmentation against the document's own vocabulary took one such paper from 363 glued runs to
  10. Ligature codepoints are folded to plain letters in the same pass (178 → 0), which is what
  produced "network e ff ects" in the narration.
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

### Hosted pages — done
GitHub Pages serves `docs/` from the `main` branch at the URLs compiled into the app:

- Privacy Policy — `https://jkleejr.github.io/research-paper-app/privacy.html`
- Support — `https://jkleejr.github.io/research-paper-app/`

If you ever move them, update `AppConfig.privacyPolicyURL` / `supportURL` and rebuild.

### Check it on a real device before submitting
Nothing since build 3 has run on hardware, and the simulator can't tell you about audio
sessions, background playback, lock screen controls, or how fast extraction really is.

Delete Paper Reader from the phone first, then Xcode → your iPhone → Product → Run. Note that
deleting doesn't clear your API key — iOS keeps Keychain items after uninstall — so use
Settings → **Remove API Key** if you want to see the no-key path a new user gets. Check:

- The library opens with the **SAMPLE** paper and no key prompt; it plays.
- Lock the phone: audio continues, lock screen shows title and controls.
- With no key stored, tapping **+** opens the key screen; saving a key there continues straight
  on to the file picker.
- Import `mksc.2018.1095.pdf` (the paper whose text was broken) and read a few paragraphs: no
  run-together words, no "e ff ects", headings on their own lines. Note how long
  "Extracting text…" takes — ~7s for 24 pages on a Mac, so expect 15–30s on device.

### Revoke the old key — done 2026-08-17
The key from the embedded-key era (`AQ.Ab8RN6Jf…`) was revoked at
[aistudio.google.com/apikey](https://aistudio.google.com/apikey). Its `Secrets.xcconfig` was
already deleted, no build had read it since the move to per-user keys, and git history is
clean of it — so nothing in the app depended on it. Shipping builds carry no key at all.

### Screenshots — done
Four 1320×2868 (6.9") images are in `screenshots/appstore/`, ready to upload in filename order:

| # | Screen | Caption |
|---|---|---|
| 01 | Library + mini player | Turn research papers into audio |
| 02 | Reader, playing | Follow along, sentence by sentence |
| 03 | Voice picker | Eight narration voices |
| 04 | API key screen | Bring your own API key |

(The plain library shot and the mini-player shot were near-duplicates, so they were
merged: the mini-player capture carries the opening caption.)

Drop them in the **6.9" box**, not 6.5" — each box accepts only its own dimensions, and
6.9" is the only one required. A 6.5" set (1242×2688) is also generated, in
`screenshots/appstore-6.5/`, if you want to fill that box too.

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

**Promotional text** (169 / 170 characters — the only field editable on a live app):
> Turn any research paper into clean, listenable audio. Import a PDF, and Paper Reader
> filters out the headers, page numbers, and citation clutter, then narrates the text.

**Description** (1,680 / 4,000 characters — paste from `description.txt`, not from here; the
lines below are wrapped for reading and would paste as hard breaks mid-sentence):
> Paper Reader turns research paper PDFs into audio you can actually listen to.
> PDFs of academic papers are hostile to text-to-speech: headers, footers, page numbers,
> inline citations, figure captions, and table fragments all get read aloud as noise.
> Paper Reader uses Google's Gemini models to clean the extracted text into a coherent
> script first, then narrates it so you hear the paper, not the layout.
> - Try it straight away — a sample paper comes ready to play, no setup, no key
>
> Import any text-based PDF from Files or iCloud Drive:
>
> - Follow along with sentence-by-sentence highlighting, or listen with the screen off
> - Background audio, lock screen controls, adjustable playback speed
> - 8 narration voices to choose from
> - Papers, audio, and progress are saved on device, so you can pick up where you left off
> - Processing resumes where it stopped if you close the app mid-paper
>
> BRING YOUR OWN API KEY:
>
> - Paper Reader has no subscription and no servers. The included sample paper plays
>   immediately, and to narrate your own papers you supply your own Google Gemini API key —
>   requests go straight from your phone to Google, billed to your own Google account.
> - Narration uses Gemini's text-to-speech model, which requires billing enabled on your
>   Google account. A typical paper costs $1–2 of Google usage; a long one can reach $3.
>   Text cleanup adds a few cents.
> - Get a key at aistudio.google.com/apikey.
>
> NOTE:
> Your key is stored in the iOS Keychain. Papers and audio never leave your device except as
> text sent to Google to be processed. Nothing is collected by the developer.
> Paper Reader reads embedded PDF text and does not perform OCR, so image-only scans won't work.

The three bullets that split one sentence in the draft are joined back into a single bullet —
the App Store renders the description as plain text, so a sentence broken across bullets reads
as three fragments. Two cost claims were also corrected against measured pricing; see below.

**Why the cost line differs from the draft.** The draft said "Text cleanup runs on Gemini's
free tier" and "roughly $1 per paper, or ~$1.75 per 50k characters". Both were changed:

- *Free tier.* Enabling billing — which TTS requires — moves the whole project to a paid tier,
  so cleanup is billed too. It is only a few cents, so the line now says that instead.
- *$1 per paper.* Verified against `gemini-3.1-flash-tts-preview` pricing ($20 per 1M audio
  output tokens, 25 tokens/second = $0.03/minute of audio) and the bundled sample's measured
  rate of 856 characters per minute: a 35k-character paper runs ~41 minutes and ~$1.25, a
  50k-character one ~$1.75, a long 70k-character one ~$2.45. Quoting "$1" would understate the
  common case, and a bill that lands above the promise is what one-star reviews are made of.
  "50k characters" was dropped as well — nobody knows their paper's character count.

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
> NO ACCOUNT OR CREDENTIALS ARE NEEDED TO REVIEW THIS APP. It ships with a sample paper that is
> already cleaned and narrated, installed into the library on first launch. Open the app, tap
> the paper badged SAMPLE ("TradingAgents: Multi-Agents LLM Financial Trading Framework") and
> press play. That demonstrates the complete reading experience: synchronized sentence
> highlighting, adjustable speed, background audio, and lock screen controls.
>
> To narrate their OWN PDFs, users supply their own Google Gemini API key, stored in the iOS
> Keychain. There is no subscription and no developer-run server — requests go directly from the
> device to Google, billed to the user's own Google account. Tapping + prompts for the key.
>
> If you would also like to test importing a PDF, you are welcome to use this key:
>
>     <OPTIONAL: A WORKING KEY WITH BILLING ENABLED>
>
> Add it via Settings → Add API Key, then tap +, choose any text-based PDF, and wait for
> processing (a few minutes for a full paper; a short PDF is faster).
>
> Privacy: the app has no backend and no analytics. PDFs, extracted text, generated audio, and
> playback progress are stored only on device; the API key is stored in the iOS Keychain. Text
> extracted from imported PDFs is sent directly from the device to Google's Gemini API using the
> user's own key. Nothing is collected by the developer, which is why the privacy label is
> "Data Not Collected."
>
> The bundled sample is used under the Creative Commons Attribution 4.0 licence, credited at the
> start of its audio. The app does not perform OCR, so image-only scanned PDFs are not supported.

The bundled sample is what removes the Guideline 2.1 risk: the reviewer gets a fully working app
with no setup. Including a key anyway is still worth it — it costs nothing if unused, and it
lets a thorough reviewer exercise the import path rather than guessing at it. Make it a
dedicated key in its own Google project with billing enabled and a low budget cap, so revoking
it later affects nothing you use.

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

1. **Guideline 2.1 — reviewer can't exercise the app.** Was the biggest risk; the bundled sample
   removes it. The reviewer opens the app and has a complete, working paper to play with no
   setup and no credentials. The optional key in the review notes is a convenience for testing
   the import path, not the thing standing between you and approval.
2. **Guideline 4.2 — minimum functionality.** An app that needs a third-party API key with
   billing enabled is unusual, and this is now the most likely rejection. It's substantially
   blunted: the app does something genuinely useful on first launch without any account, and the
   description says plainly what the key is for. What's left in reserve if Apple still raises it
   is widening the no-key experience — bundling two or three samples, and letting an imported
   paper be read with the iOS built-in speech synthesiser when no key is present.
3. **Guideline 3.1.1 — in-app purchase.** Should not apply: the app sells nothing, and users pay
   Google directly for their own API usage rather than buying digital content in-app. If Apple
   raises it, the argument is that this is a bring-your-own-credentials app in the same shape as
   an email or SSH client, not a storefront.
4. **Minor polish, not a rejection risk:** tapping a paper that is still processing or has failed
   opens `RawTextView`, which is still labelled internally as a pipeline debug view and shows raw
   per-page text dumps. Worth replacing with a proper status screen before or shortly after
   launch.
