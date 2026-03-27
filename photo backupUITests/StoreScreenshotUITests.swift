import XCTest

/// Generates PNGs for README and App Store–style marketing.
/// Skipped when using the **Archive Angel** scheme (see that scheme’s SkippedTests). Run via `./scripts/capture-store-screenshots.sh`.
/// Output: `docs/store-screenshots/README/*.png` (paths relative to repo root).
final class StoreScreenshotUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCaptureStoreScreenshots() throws {
        let app = XCUIApplication()
        app.launch()

        let photoAccessMonitor = addUIInterruptionMonitor(withDescription: "Photo access") { alert in
            for title in ["Allow Access to All Photos", "Allow Full Access", "OK", "Allow"] {
                let button = alert.buttons[title]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }
        defer { removeUIInterruptionMonitor(photoAccessMonitor) }

        // Nudge the run loop so a permission alert can be handled by the interruption monitor.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        try saveScreenshot(named: "01-backup")

        app.swipeUp()
        app.swipeUp()
        try saveScreenshot(named: "02-backup-scroll")

        app.tabBars.buttons["History"].tap()
        waitForTabTransition()
        try saveScreenshot(named: "03-history")

        app.swipeUp()
        try saveScreenshot(named: "04-history-scroll")

        app.tabBars.buttons["Settings"].tap()
        waitForTabTransition()
        try saveScreenshot(named: "05-settings")

        app.swipeUp()
        app.swipeUp()
        try saveScreenshot(named: "06-settings-scope")
    }

    private func waitForTabTransition() {
        Thread.sleep(forTimeInterval: 0.6)
    }

    private func saveScreenshot(named name: String) throws {
        let dir = Self.screenshotOutputDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(name).png", isDirectory: false)
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try data.write(to: url, options: .atomic)
    }

    private static var screenshotOutputDirectory: URL {
        let sourceFile = URL(fileURLWithPath: #filePath)
        let repoRoot = sourceFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return repoRoot.appendingPathComponent("docs/store-screenshots/README", isDirectory: true)
    }
}
