# Screenshot pipeline

Regenerates the App Store screenshots in `screenshots/` end to end. Everything is
repeatable, so a redesign just means running these three steps again.

Output is 1320×2868 — the 6.9" size App Store Connect requires, and the only iPhone
size needed since the app is iPhone-only.

## 1. Stage a sample library

`SeedLibrary.swift` writes `paper.json` files plus silent WAV audio of the correct
duration into a folder, reusing the app's own `Paper`/`ChunkPlanner` types so the
JSON is exactly what the real pipeline produces. Silent audio means playback,
highlighting, and progress all behave for real without spending any API credits.

```sh
SIM=$(xcrun simctl list devices available | grep "iPhone 17 Pro Max" | head -1 | sed -E 's/.*\(([-0-9A-F]+)\).*/\1/')
xcrun simctl boot "$SIM"

swiftc -O Tools/screenshots/SeedLibrary.swift \
  PaperReader/Models/Paper.swift PaperReader/Services/SentenceSegmenter.swift \
  -o /tmp/seedtool
/tmp/seedtool /tmp/seed

xcodebuild -project PaperReader.xcodeproj -scheme PaperReader \
  -destination "id=$SIM" -configuration Debug -derivedDataPath build/dd build
xcrun simctl install "$SIM" build/dd/Build/Products/Debug-iphonesimulator/PaperReader.app

CONT=$(xcrun simctl get_app_container "$SIM" com.jklwjr.PaperReader data)
rm -rf "$CONT/Library/Application Support/Papers"
mkdir -p "$CONT/Library/Application Support/Papers"
cp -R /tmp/seed/. "$CONT/Library/Application Support/Papers/"

# Apple's convention: 9:41, full bars, full battery.
xcrun simctl status_bar "$SIM" override --time "9:41" --batteryState discharging \
  --batteryLevel 100 --cellularMode active --cellularBars 4 --wifiMode active --wifiBars 3
```

## 2. Capture

`PaperReaderUITests/ScreenshotTests.swift` drives the app and captures each screen at
full device resolution. It launches with `-uiTestAPIKey`, a Debug-only hook (see
`AppConfig.geminiAPIKey`) that stands in a key so the "add your key" banner stays out
of marketing shots. Release builds ignore it entirely.

```sh
xcodebuild test -project PaperReader.xcodeproj -scheme PaperReader \
  -destination "id=$SIM" -derivedDataPath build/dd -resultBundlePath build/results.xcresult

rm -rf build/shots
xcrun xcresulttool export attachments --path build/results.xcresult --output-path build/shots
python3 - <<'PY'
import json, os, shutil
m = json.load(open("build/shots/manifest.json"))
for test in m:
    for a in test.get("attachments", []):
        f = a["exportedFileName"]
        if f.endswith(".png"):
            name = (a.get("suggestedHumanReadableName") or f).split("_0_")[0]
            shutil.copy(os.path.join("build/shots", f),
                        os.path.join("screenshots/raw", name + ".png"))
PY
```

## 3. Compose

`compose.py` lays each capture on the caption background and writes the uploadable
files to `screenshots/appstore/`. Edit the `FRAMES` list to change which captures are
used, their order, and their captions.

```sh
python3 Tools/screenshots/compose.py     # needs Pillow
```

Upload `screenshots/appstore/*.png` in filename order.
