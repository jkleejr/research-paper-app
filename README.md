# Paper Reader

An iOS app that turns research paper PDFs into narrated audio. It extracts the text, uses
Google's Gemini models to clean out page furniture, citation clutter, and table debris, then
narrates the result with Gemini text-to-speech — so you hear the paper rather than the layout.

- Sentence-by-sentence highlighting, background audio, lock screen controls, variable speed
- Papers, audio, and playback position persist on device; a killed app resumes mid-pipeline
- Audio is generated per chunk on demand and cached, so playback starts before the whole paper is

<img width="603" height="1311" alt="IMG_6210" src="https://github.com/user-attachments/assets/5a7de76e-00e3-4464-bd46-cb23c0029c11" />

<img width="603" height="1311" alt="IMG_6209" src="https://github.com/user-attachments/assets/0dbb4758-98aa-4176-8cd1-872a1fa46a9d" />

<img width="603" height="1311" alt="IMG_6211" src="https://github.com/user-attachments/assets/f3be6c05-3c1f-4896-9f85-77c643f5306f" />

## Bring your own API key

There is no backend and no subscription. Each user supplies their own Gemini API key, stored in
the iOS Keychain, and requests go straight from the device to Google billed to that user's own
account. Get one at [aistudio.google.com/apikey](https://aistudio.google.com/apikey). Text
cleanup runs on the free tier; text-to-speech requires billing enabled.

**Never commit an API key or embed one in a build.**

## Building

The Xcode project is generated — edit `project.yml`, not the `.pbxproj`:

```sh
brew install xcodegen
xcodegen generate
open PaperReader.xcodeproj
```

Requires Xcode 26+, iOS 17+ deployment target, iPhone only.

## Layout

| Path | What's in it |
|---|---|
| `PaperReader/Services/` | Gemini client, PDF extraction, script generation, TTS prefetch + cache, playback |
| `PaperReader/Services/TextRepair.swift` | Rebuilds word spacing in PDFs that extract without spaces |
| `Tools/sample/` | Generates the bundled sample paper shipped in `Resources/SampleLibrary/` |
| `PaperReader/Views/` | SwiftUI screens — library, reader, player, settings, key setup |
| `PaperReader/Models/` | `Paper` and its pipeline status |
| `docs/` | Support and privacy pages published via GitHub Pages |
| `screenshots/` | App Store screenshots (`appstore/`) and raw device captures (`raw/`) |
| `Tools/screenshots/` | Repeatable pipeline that regenerates both |
| `APP_STORE_SUBMISSION.md` | Release checklist, listing copy, App Review notes |
