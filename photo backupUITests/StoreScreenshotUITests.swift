import UIKit
import XCTest

/// Generates PNGs for README and App Store–style marketing.
/// Skipped when using the **Archive Angel** scheme (see that scheme’s SkippedTests). Run via `./scripts/capture-store-screenshots.sh`.
/// Output: `docs/store-screenshots/iphone/*.png` and `docs/store-screenshots/ipad/*.png` (paths relative to repo root).
final class StoreScreenshotUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCaptureStoreScreenshots_iPhone() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone, "Run on an iPhone Simulator (see capture script destination).")
        try runCaptureFlow(outputSubfolder: "iphone")
    }

    func testCaptureStoreScreenshots_iPad() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "Run on an iPad Simulator (see capture script destination).")
        try runCaptureFlow(outputSubfolder: "ipad")
    }

    private func runCaptureFlow(outputSubfolder: String) throws {
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

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        try saveScreenshot(named: "01-backup", subfolder: outputSubfolder)

        app.swipeUp()
        app.swipeUp()
        try saveScreenshot(named: "02-backup-scroll", subfolder: outputSubfolder)

        tapTab(named: "History", app: app)
        waitForTabTransition()
        try saveScreenshot(named: "03-history", subfolder: outputSubfolder)

        app.swipeUp()
        try saveScreenshot(named: "04-history-scroll", subfolder: outputSubfolder)

        tapTab(named: "Settings", app: app)
        waitForTabTransition()
        try saveScreenshot(named: "05-settings", subfolder: outputSubfolder)

        app.swipeUp()
        app.swipeUp()
        try saveScreenshot(named: "06-settings-scope", subfolder: outputSubfolder)
    }

    /// iPhone uses a tab bar; iPad may use a sidebar or top tabs with the same labels.
    private func tapTab(named title: String, app: XCUIApplication) {
        let tabBar = app.tabBars.buttons[title]
        if tabBar.waitForExistence(timeout: 2) {
            tabBar.tap()
            return
        }
        let labeled = app.buttons[title].firstMatch
        if labeled.waitForExistence(timeout: 2) {
            labeled.tap()
            return
        }
        XCTFail("Could not find tab or button labeled \(title).")
    }

    private func waitForTabTransition() {
        Thread.sleep(forTimeInterval: 0.6)
    }

    private func saveScreenshot(named name: String, subfolder: String) throws {
        let dir = Self.screenshotOutputDirectory(subfolder: subfolder)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(name).png", isDirectory: false)
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try data.write(to: url, options: .atomic)
    }

    private static func screenshotOutputDirectory(subfolder: String) -> URL {
        let sourceFile = URL(fileURLWithPath: #filePath)
        let repoRoot = sourceFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return repoRoot.appendingPathComponent("docs/store-screenshots/\(subfolder)", isDirectory: true)
    }
}
