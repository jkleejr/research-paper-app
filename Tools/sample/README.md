# Bundled sample paper

The app ships one real paper, already cleaned and narrated, in
`PaperReader/Resources/SampleLibrary/`. It's installed into the library on first launch so a
new user — and an App Review tester — can hear exactly what the app does before getting an
API key.

It is generated **once, by a developer**, and committed. Users never pay for it, and no API
key ships in the binary. At runtime every chunk is already cached, so the prefetcher makes no
API calls, and the audio plays straight out of the bundle rather than being copied into the
user's storage.

## What's in it

Currently *TradingAgents: Multi-Agents LLM Financial Trading Framework* (arXiv:2412.20138) by
Yijia Xiao, Edward Sun, Di Luo and Wei Wang — abstract and introduction only, about six
minutes of audio.

**Check the licence before swapping in a different paper.** Bundling a paper in a shipped app
is redistribution, which most arXiv licences do not permit. This one is
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/), which does, provided the work is
credited and changes are noted. That attribution is the spoken preamble at the top of the
script (see `preamble` in `main.swift`) — it names the paper, the authors and the licence, and
says the text was abridged and synthetically narrated. If you change the paper, change the
preamble to match, and confirm the new paper's licence allows redistribution.

## Regenerating

Needs a Gemini API key with **billing enabled** — TTS is not on the free tier. Costs roughly
$0.30 for a six-minute excerpt.

```sh
P=PaperReader
swiftc -DDEBUG -O Tools/sample/main.swift \
  $P/Models/Paper.swift $P/App/AppConfig.swift $P/Services/APIKeyStore.swift \
  $P/Services/GeminiClient.swift $P/Services/ScriptGenerator.swift $P/Services/TTSService.swift \
  $P/Services/AudioCache.swift $P/Services/PaperStore.swift $P/Services/SentenceSegmenter.swift \
  $P/Services/PDFTextExtractor.swift $P/Services/SampleLibrary.swift \
  -o /tmp/generate-sample

GEMINI_API_KEY=$(cat ~/.paperreader_key) /tmp/generate-sample \
  "/path/to/paper.pdf" 1 2 PaperReader/Resources/SampleLibrary
```

The two numbers are the first and last PDF page to include. Keep the excerpt short — audio is
24 kHz mono WAV at about 2.9 MB per minute, and it all ships in the app.

The tool reuses the app's own `PDFTextExtractor`, `ScriptGenerator` prompt, `SentenceSegmenter`,
`ChunkPlanner` and `TTSService`, so the sample is byte-for-byte what a real import produces.
`-DDEBUG` enables the `uiTestAPIKey` hook in `AppConfig` that lets the tool supply a key without
touching the Keychain.

After regenerating, bump `installedKey` in `SampleLibrary.swift` (`didInstallSample.v1` →
`.v2`) so existing installs pick up the new sample.
