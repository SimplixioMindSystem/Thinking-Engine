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
        let root = override?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? URL(fileURLWithPath: override!, isDirectory: true)
            : URL(fileURLWithPath: "/Users/pierre/Code/CortexOSLLM/CortexOSApp/screenshot_results", isDirectory: true)
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
        app.launch()
        // Give the app time to fully render
        sleep(2)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    }

    @discardableResult
    private func captureWindow(_ name: String) -> XCUIScreenshot {
        let screenshot: XCUIScreenshot
#if os(macOS)
        screenshot = app.windows.firstMatch.screenshot()
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
    @discardableResult
    private func openSidebarItem(_ title: String, identifier: String) -> XCUIElement {
        let sidebar = app.outlines.firstMatch
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5), "Expected the macOS sidebar to be visible.")

        let byIdentifier = sidebar.descendants(matching: .any)
            .matching(identifier: "sidebar.\(identifier)")
            .firstMatch
        if byIdentifier.waitForExistence(timeout: 2) {
            byIdentifier.click()
            return byIdentifier
        }

        let byLabel = sidebar.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", title))
            .firstMatch
        XCTAssertTrue(byLabel.waitForExistence(timeout: 5), "Expected the \(title) sidebar item to be visible.")
        byLabel.click()
        return byLabel
    }

    func testCaptureFocusSidebar() throws {
        // Focus is the default selection
        sleep(1)
        captureWindow("01_focus")
    }

    func testCaptureInsightsSidebar() throws {
        openSidebarItem("Insights", identifier: "insights")
        sleep(1)

        captureWindow("02_insights")
    }

    func testCaptureReviewQueueSidebar() throws {
        openSidebarItem("Review Queue", identifier: "reviewQueue")
        sleep(1)

        captureWindow("03_queues")
    }

    func testCaptureMemorySidebar() throws {
        openSidebarItem("Memory", identifier: "memory")
        sleep(1)

        captureWindow("04_memory")
    }

    func testCaptureDecisionsSidebar() throws {
        openSidebarItem("Decisions", identifier: "decisions")
        sleep(1)

        captureWindow("05_decisions")
    }

    func testCaptureSettingsSidebar() throws {
        openSidebarItem("Settings", identifier: "settings")
        sleep(1)
        captureWindow("06_settings")
    }

    func testSettingsSyncButtonKeepsAppResponsive() throws {
        openSidebarItem("Settings", identifier: "settings")

        let syncButton = app.buttons.containing(
            NSPredicate(format: "label CONTAINS[c] 'Sync'")
        ).firstMatch
        XCTAssertTrue(syncButton.waitForExistence(timeout: 5))
        syncButton.click()

        openSidebarItem("Focus", identifier: "focus")

        let focusContent = app.descendants(matching: .any)
            .matching(identifier: "focus.screen")
            .firstMatch
        XCTAssertTrue(focusContent.waitForExistence(timeout: 5))
    }
    #endif
}
