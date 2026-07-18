//
//  ScreenshotTests.swift
//  CortexOS
//
//  Automated App Store screenshot capture.
//  Navigates through every key screen and saves a screenshot.
//

import XCTest

final class ScreenshotTests: XCTestCase {
#if os(macOS)
    let app = XCUIApplication(bundleIdentifier: "me.ph7.cortexos.macos")
#else
    let app = XCUIApplication()
#endif
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
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "Expected the macOS app window to exist before capturing \(name).")
        screenshot = window.screenshot()
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

    func testCaptureReviewHistory() throws {
        // Review history is the compact decision/replay surface on iPhone.
        let reviewButton = app.navigationBars.buttons["Review history"]
        XCTAssertTrue(reviewButton.waitForExistence(timeout: 5))
        reviewButton.tap()
        sleep(1)

        captureWindow("02_review")
    }

    func testReviewNotesSearch() throws {
        let reviewButton = app.navigationBars.buttons["Review history"]
        XCTAssertTrue(reviewButton.waitForExistence(timeout: 5))
        reviewButton.tap()

        let notesSegment = app.buttons["Notes"]
        XCTAssertTrue(notesSegment.waitForExistence(timeout: 5))
        notesSegment.tap()

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("offline")

        let matchingNote = app.staticTexts["Offline continuity increases trust"]
        XCTAssertTrue(
            matchingNote.waitForExistence(timeout: 5),
            "Expected hybrid on-device search to return the matching note."
        )
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

        XCTAssertTrue(
            app.staticTexts["Semantic search"].waitForExistence(timeout: 5),
            "Expected on-device semantic index status in Settings."
        )

        captureWindow("04_settings")
    }
    #endif

    // MARK: - macOS Screenshots

    #if os(macOS)
    private func launchMacApp(sectionID: String? = nil, searchQuery: String? = nil) {
        if app.state != .notRunning {
            app.terminate()
        }

        var arguments = ["-UITests", "-Screenshots"]
        if let sectionID {
            arguments += ["-mac-section", sectionID]
        }
        if let searchQuery {
            arguments += ["-UITestSearchQuery", searchQuery]
        }

        app.launchArguments = arguments
        app.launch()
        sleep(2)
    }

    func testCaptureFocusSidebar() throws {
        launchMacApp(sectionID: "focus")
        let focusHeading = app.staticTexts["Today’s 3 priorities"].firstMatch
        XCTAssertTrue(focusHeading.waitForExistence(timeout: 5), "Expected the Focus detail content to load.")
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
        XCTAssertTrue(
            app.staticTexts["Semantic search"].waitForExistence(timeout: 5),
            "Expected on-device semantic index status in macOS Settings."
        )
        captureWindow("06_settings")
    }

    func testMacNotesSearchUsesEmbeddedIndex() throws {
        launchMacApp(sectionID: "notes", searchQuery: "offline")

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        XCTAssertEqual(searchField.value as? String, "offline")

        let matchingNote = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Offline continuity increases trust")
        ).firstMatch
        XCTAssertTrue(
            matchingNote.waitForExistence(timeout: 5),
            "Expected macOS hybrid on-device search to return the matching note."
        )
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
