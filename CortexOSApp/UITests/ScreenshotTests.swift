//
//  ScreenshotTests.swift
//  CortexOS
//
//  Automated App Store screenshot capture.
//  Navigates through every key screen and saves a screenshot.
//

import XCTest

final class ScreenshotTests: XCTestCase {
    let app = XCUIApplication()
    private lazy var outputDirectory: URL = {
        let override = ProcessInfo.processInfo.environment["SCREENSHOT_OUTPUT_DIR"]
        let root: URL
        if override?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            root = URL(fileURLWithPath: override!, isDirectory: true)
        } else {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("simplixio_screenshot_results", isDirectory: true)
        }
#if os(macOS)
        return root.appendingPathComponent("mac_raw", isDirectory: true)
#elseif os(iOS)
        return root.appendingPathComponent("iphone_raw", isDirectory: true)
#else
        return root
#endif
    }()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments += ["-UITests", "-Screenshots"]
#if os(iOS)
        app.launch()
#endif
        // Give the app time to fully render
        sleep(2)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    }

    @discardableResult
    private func captureWindow(_ name: String) -> XCUIScreenshot {
        let screenshot: XCUIScreenshot
#if os(macOS)
        app.activate()
        let rootView = app.descendants(matching: .any)
            .matching(identifier: "mac.root")
            .firstMatch
        XCTAssertTrue(rootView.waitForExistence(timeout: 5), "Expected the macOS app root view to exist before capturing \(name).")
        screenshot = rootView.screenshot()
#else
        screenshot = app.screenshot()
#endif

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let path = outputDirectory.appendingPathComponent("\(name).png")
        do {
            try screenshot.pngRepresentation.write(to: path)
        } catch {
            XCTFail("Failed to write screenshot \(name): \(error)")
        }
        return screenshot
    }

    // MARK: - iOS Screenshots

    #if os(iOS)
    func testCaptureFocusTab() throws {
        // Focus tab is the default landing screen
        captureWindow("01_focus")
    }

    func testCaptureDecideTab() throws {
        // Tap the Decide tab
        let decideTab = app.tabBars.buttons["Decide"]
        XCTAssertTrue(decideTab.waitForExistence(timeout: 5))
        decideTab.tap()
        sleep(1)

        captureWindow("02_decide")
    }

    func testCaptureCaptureTab() throws {
        // Tap the Capture tab
        let captureTab = app.tabBars.buttons["Capture"]
        XCTAssertTrue(captureTab.waitForExistence(timeout: 5))
        captureTab.tap()
        sleep(1)

        captureWindow("03_capture")
    }

    func testCaptureSettings() throws {
        // Tap the gear icon to open Settings
        let settingsButton = app.navigationBars.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'gear' OR label CONTAINS[c] 'settings' OR identifier CONTAINS[c] 'gear'")
        ).firstMatch

        if settingsButton.waitForExistence(timeout: 5) {
            settingsButton.tap()
        } else {
            // Try toolbar buttons
            let toolbarButtons = app.buttons
            for i in 0..<toolbarButtons.count {
                let btn = toolbarButtons.element(boundBy: i)
                if btn.label.lowercased().contains("gear") || btn.label.lowercased().contains("setting") {
                    btn.tap()
                    break
                }
            }
        }
        sleep(1)

        captureWindow("04_settings")
    }
    #endif

    // MARK: - macOS Screenshots

    #if os(macOS)
    private func launchMacApp(sectionID: String? = nil) {
        if app.state == .runningForeground {
            app.terminate()
        }

        var arguments = ["-UITests", "-Screenshots"]
        if let sectionID {
            arguments += ["-mac-section", sectionID]
        }

        app.launchArguments = arguments
        app.launch()
        sleep(2)
    }

    func testCaptureFocusSidebar() throws {
        launchMacApp(sectionID: "focus")
        // Focus is the default selection
        captureWindow("01_focus")
    }

    func testCaptureInsightsSidebar() throws {
        launchMacApp(sectionID: "insights")
        captureWindow("02_insights")
    }

    func testCaptureReviewQueueSidebar() throws {
        launchMacApp(sectionID: "reviewQueue")
        captureWindow("03_queues")
    }

    func testCaptureMemorySidebar() throws {
        launchMacApp(sectionID: "memory")
        captureWindow("04_memory")
    }

    func testCaptureDecisionsSidebar() throws {
        launchMacApp(sectionID: "decisions")
        captureWindow("05_decisions")
    }

    func testCaptureSettingsSidebar() throws {
        launchMacApp(sectionID: "settings")
        captureWindow("06_settings")
    }

    func testSettingsSyncButtonKeepsAppResponsive() throws {
        launchMacApp(sectionID: "settings")

        let syncButton = app.buttons.containing(
            NSPredicate(format: "label CONTAINS[c] 'Sync'")
        ).firstMatch
        XCTAssertTrue(syncButton.waitForExistence(timeout: 5))
        syncButton.click()

        let settingsContent = app.descendants(matching: .any)
            .matching(identifier: "settings.screen")
            .firstMatch
        XCTAssertTrue(settingsContent.waitForExistence(timeout: 5))
    }
    #endif
}
