import XCTest

/// Captures App Store screenshots at full device resolution.
///
/// Run against a 6.9" simulator (iPhone 17 Pro Max) whose library has been
/// staged with sample papers, then export the attachments from the result
/// bundle. See APP_STORE_SUBMISSION.md.
final class ScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        // Stands in a key so the "add your key" banner stays out of marketing
        // shots; Debug-only, see AppConfig.geminiAPIKey.
        app.launchArguments = ["-uiTestAPIKey", "AIzaScreenshotPlaceholder"]
        app.launch()
    }

    func testCaptureScreenshots() throws {
        let library = app.staticTexts["My Papers"]
        XCTAssertTrue(library.waitForExistence(timeout: 10), "library never appeared")
        snap("01-library")

        // The bundled sample — real licensed content with real narration, and
        // the one paper guaranteed to exist on a fresh install. Tap the card
        // button itself; tapping its title label doesn't activate the row.
        let card = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'TradingAgents'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), "sample paper missing from library")

        // The reader's close button only exists once the cover is up, so it's
        // the gate that proves we left the library — unlike the sentence
        // counter, which the mini player shows too. Retry: a tap on a list row
        // occasionally doesn't register while the list is still settling.
        var opened = false
        for _ in 0..<4 where !opened {
            card.tap()
            opened = waitForHittable("xmark", timeout: 4, lowest: false) != nil
        }
        XCTAssertTrue(opened, "reader didn't open\n\(app.debugDescription)")

        guard let play = waitForHittable("play.circle.fill") else {
            return XCTFail("reader controls never appeared\n\(app.debugDescription)")
        }
        // Seek past the attribution preamble so the shots show paper prose
        // rather than the credit boilerplate.
        let body = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Significant progress has been made'")).firstMatch
        if body.waitForExistence(timeout: 3) {
            body.tap()
            Thread.sleep(forTimeInterval: 1.0)
        }
        snap("02-reader")

        // Playing: highlight advances and the control flips to pause.
        let started = sentenceIndex()
        play.tap()
        XCTAssertNotNil(waitForHittable("pause.circle.fill", timeout: 5),
                        "playback never started — bundled audio may be unreadable")
        Thread.sleep(forTimeInterval: 8)
        snap("03-reader-playing")

        // Proves the audio really is playing out of the app bundle: the playhead
        // has to have advanced on its own, with no API call possible.
        let reached = sentenceIndex()
        XCTAssertGreaterThan(reached, started,
                             "playhead stuck at sentence \(started) — bundled audio not playing")
        print("SAMPLE PLAYBACK OK — advanced \(started) -> \(reached) of 44")

        // Back to the library; the mini player now shows what's playing.
        XCTAssertTrue(returnToLibrary(), "reader wouldn't close\n\(app.debugDescription)")
        Thread.sleep(forTimeInterval: 1.0)
        snap("05-library-miniplayer")

        // Settings.
        guard let gear = waitForHittable("gearshape", timeout: 5) else {
            return XCTFail("no settings button\n\(app.debugDescription)")
        }
        gear.tap()
        Thread.sleep(forTimeInterval: 0.4)
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5),
                      "settings never appeared\n\(app.debugDescription)")
        Thread.sleep(forTimeInterval: 0.6)
        snap("06-settings")

        // The bring-your-own-key screen, then back to Settings.
        let changeKey = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Change API Key'"))
            .firstMatch
        if changeKey.waitForExistence(timeout: 3) {
            changeKey.tap()
            XCTAssertTrue(app.staticTexts["Gemini API Key"].waitForExistence(timeout: 5))
            Thread.sleep(forTimeInterval: 0.6)
            snap("07-api-key")
            app.buttons["Cancel"].firstMatch.tap()
            Thread.sleep(forTimeInterval: 0.8)
        }

        // Voice menu last — it overlays everything, so nothing follows it.
        let voiceRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Voice'")).firstMatch
        if voiceRow.waitForExistence(timeout: 3) {
            voiceRow.tap()
            Thread.sleep(forTimeInterval: 1.2)
            snap("08-voices")
        } else {
            XCTFail("voice picker not found\n\(app.debugDescription)")
        }
    }

    /// Screens stack (the reader covers the library), so the same SF Symbol can
    /// match several times over — and a covered element can still report itself
    /// hittable. Disambiguate by position: controls at the bottom of the screen
    /// take the lowest match, the reader's close button the highest.
    @discardableResult
    private func waitForHittable(_ identifier: String, timeout: TimeInterval = 10,
                                 lowest: Bool = true) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let matches = app.buttons.matching(identifier: identifier)
            let hittable = (0..<matches.count)
                .map { matches.element(boundBy: $0) }
                .filter { $0.exists && $0.isHittable }
            if let best = lowest ? hittable.max(by: { $0.frame.maxY < $1.frame.maxY })
                                 : hittable.min(by: { $0.frame.maxY < $1.frame.maxY }) {
                return best
            }
            Thread.sleep(forTimeInterval: 0.3)
        } while Date() < deadline
        return nil
    }

    /// Closes the reader and waits until the library is genuinely in front.
    ///
    /// The reader's close button can report itself hittable before the cover
    /// has settled, so a single tap sometimes lands on nothing. The library's
    /// gear button being hittable is the only reliable signal that we're back —
    /// the mini player shows a "Sentence N of M" label too, so that isn't one.
    private func returnToLibrary() -> Bool {
        for _ in 0..<6 {
            if waitForHittable("gearshape", timeout: 2) != nil { return true }
            // Highest xmark = the reader's close button, not the mini player's.
            waitForHittable("xmark", timeout: 2, lowest: false)?.tap()
            Thread.sleep(forTimeInterval: 0.8)
        }
        return false
    }

    /// Current position from the reader's "Sentence N of M" counter.
    private func sentenceIndex() -> Int {
        let label = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Sentence '")).firstMatch
        guard label.exists, let n = label.label.split(separator: " ").dropFirst().first else { return 0 }
        return Int(n) ?? 0
    }

    private func snap(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
