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

    func testFocusContentRemainsScrollable() throws {
        let heading = app.staticTexts["Today’s 3 priorities"].firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        let originalY = heading.frame.minY

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30))
        start.press(forDuration: 0.05, thenDragTo: end)

        XCTAssertLessThan(
            heading.frame.minY,
            originalY - 10,
            "Focus content should scroll rather than overlap its heading."
        )
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

    func testCaptureEditorKeepsFocusAndAcceptsWriting() throws {
        let captureTab = app.tabBars.buttons["Capture"]
        XCTAssertTrue(captureTab.waitForExistence(timeout: 5))
        captureTab.tap()

        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("A thought that should remain editable")

        XCTAssertTrue(
            (editor.value as? String)?.contains("remain editable") == true,
            "Tapping the writing surface must keep keyboard focus."
        )
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
            app.navigationBars["Settings"].waitForExistence(timeout: 5),
            "Expected the Settings sheet to be visible."
        )

        captureWindow("04_settings")
    }
    #endif

    // MARK: - macOS Screenshots

    #if os(macOS)
    private func launchMacApp(
        sectionID: String? = nil,
        searchQuery: String? = nil,
        usePreviewContent: Bool = true
    ) {
        if app.state != .notRunning {
            app.terminate()
        }

        var arguments = ["-UITests", "-Screenshots"]
        if !usePreviewContent {
            arguments.append("-UITestsNoDemo")
        }
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

    func testCaptureMacCaptureSidebar() throws {
        launchMacApp(sectionID: "capture")
        XCTAssertTrue(app.staticTexts["Capture without sorting first"].waitForExistence(timeout: 5))
        captureWindow("02_capture")
    }

    func testCaptureWeeklyReviewSidebar() throws {
        launchMacApp(sectionID: "weeklyReview")
        XCTAssertTrue(app.staticTexts["Top Repeated Priorities"].waitForExistence(timeout: 5))
        captureWindow("03_weekly_review")
    }

    func testCaptureDecisionReplaySidebar() throws {
        launchMacApp(sectionID: "decisionReplay")
        XCTAssertTrue(app.staticTexts["Final Priorities"].waitForExistence(timeout: 5))
        captureWindow("04_decision_replay")
    }

    func testCaptureNewsletterSidebar() throws {
        launchMacApp(sectionID: "newsletter")
        XCTAssertTrue(app.staticTexts["Public-safe draft"].waitForExistence(timeout: 5))
        captureWindow("05_newsletter")
    }

    func testCaptureInsightsSidebar() throws {
        launchMacApp(sectionID: "insights")
        let insightsItem = app.descendants(matching: .any)
            .matching(identifier: "sidebar.insights")
            .firstMatch
        XCTAssertTrue(
            insightsItem.waitForExistence(timeout: 5),
            "The selected advanced section should be visible in the sidebar."
        )
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
            app.staticTexts["Private semantic search"].waitForExistence(timeout: 5),
            "Expected private-search status in macOS Settings."
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
        launchMacApp(sectionID: "settings", usePreviewContent: false)

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

    func testSidebarRemainsStableAcrossCoreNavigation() throws {
        launchMacApp(sectionID: "focus")

        for identifier in ["sidebar.notes", "sidebar.focus", "sidebar.settings", "sidebar.focus"] {
            let item = app.descendants(matching: .any)
                .matching(identifier: identifier)
                .firstMatch
            XCTAssertTrue(item.waitForExistence(timeout: 5), "Expected \(identifier) in the sidebar.")
            item.click()
        }

        let focus = app.descendants(matching: .any)
            .matching(identifier: "sidebar.focus")
            .firstMatch
        let root = app.descendants(matching: .any)
            .matching(identifier: "mac.root")
            .firstMatch
        XCTAssertTrue(root.exists)
        XCTAssertGreaterThan(focus.frame.minY, root.frame.minY)
        XCTAssertLessThan(
            focus.frame.minY - root.frame.minY,
            180,
            "The sidebar should begin near the toolbar instead of leaving a large empty band."
        )
    }
    #endif
}
