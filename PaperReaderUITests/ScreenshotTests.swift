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

        // Reader, paused at the saved position.
        let paper = app.staticTexts["Attention Is All You Need"]
        XCTAssertTrue(paper.waitForExistence(timeout: 5))
        paper.tap()
        guard let play = waitForHittable("play.circle.fill") else {
            return XCTFail("reader controls never appeared\n\(app.debugDescription)")
        }
        snap("02-reader")

        // Playing: highlight advances and the control flips to pause.
        play.tap()
        _ = waitForHittable("pause.circle.fill")
        Thread.sleep(forTimeInterval: 2.5)
        snap("03-reader-playing")

        // Back to the library; the mini player now shows what's playing.
        waitForHittable("xmark")?.tap()
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1.0)
        snap("05-library-miniplayer")

        // Settings.
        guard let gear = waitForHittable("gearshape", timeout: 5) else {
            return XCTFail("no settings button\n\(app.debugDescription)")
        }
        gear.tap()
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
    /// match several times over. Take the bottom-most element that's actually
    /// hittable — for this app's layouts that's the one on the visible screen.
    @discardableResult
    private func waitForHittable(_ identifier: String, timeout: TimeInterval = 10) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let matches = app.buttons.matching(identifier: identifier)
            let hittable = (0..<matches.count)
                .map { matches.element(boundBy: $0) }
                .filter { $0.exists && $0.isHittable }
            if let best = hittable.max(by: { $0.frame.maxY < $1.frame.maxY }) {
                return best
            }
            Thread.sleep(forTimeInterval: 0.3)
        } while Date() < deadline
        return nil
    }

    private func snap(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
