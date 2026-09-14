import XCTest
import UIKit

@MainActor
final class PhotoTinderUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        #if targetEnvironment(simulator)
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SIMULATOR_UDID"] == "34C20ACC-6657-467B-BAF1-CF34097AE244", "UI tests require the named disposable simulator; never run on personal libraries.")
        #else
        throw XCTSkip("Destructive UI tests are simulator-only.")
        #endif
    }

    private func launch(reset: Bool = true, extra: [String] = [], authorize: Bool = true) {
        if reset { app.resetAuthorizationStatus(for: .photos) }
        app.launchArguments = ["--ui-testing"] + (reset ? ["--reset-review"] : []) + extra
        app.launch()
        if authorize, app.buttons["requestAccess"].waitForExistence(timeout: 3) {
            app.buttons["requestAccess"].tap()
            let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow Full Access"]
            XCTAssertTrue(allow.waitForExistence(timeout: 10)); allow.tap()
        }
    }
    private func waitEnabled(_ id: String) {
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: 15), "Missing \(id)")
        XCTAssertTrue(NSPredicate(format: "enabled == true").evaluate(with: button) || XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: button)], timeout: 15) == .completed)
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    private func assertMediaCardHasVariedPixels() throws {
        let screenshot = app.screenshot()
        let image = try XCTUnwrap(screenshot.image.cgImage)
        let appFrame = app.frame
        let cardFrame = app.buttons["mediaCard"].frame.intersection(appFrame)
        guard !appFrame.isEmpty, !cardFrame.isEmpty else {
            XCTFail("The visible media card must have a nonempty frame.")
            return
        }
        let scaleX = CGFloat(image.width) / appFrame.width
        let scaleY = CGFloat(image.height) / appFrame.height
        let cropRect = CGRect(
            x: (cardFrame.minX - appFrame.minX) * scaleX,
            y: (cardFrame.minY - appFrame.minY) * scaleY,
            width: cardFrame.width * scaleX,
            height: cardFrame.height * scaleY
        ).integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let card = try XCTUnwrap(image.cropping(to: cropRect))
        var pixels = [UInt8](repeating: 0, count: 32 * 32 * 4)
        let colorCount = try pixels.withUnsafeMutableBytes { buffer in
            let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: 32, height: 32, bitsPerComponent: 8,
                bytesPerRow: 32 * 4, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ))
            context.interpolationQuality = .none
            context.draw(card, in: CGRect(x: 0, y: 0, width: 32, height: 32))
            let bytes = buffer.bindMemory(to: UInt8.self)
            var colors = Set<Int>()
            for offset in stride(from: 0, to: bytes.count, by: 4) {
                colors.insert(Int(bytes[offset] / 16) << 8 | Int(bytes[offset + 1] / 16) << 4 | Int(bytes[offset + 2] / 16))
            }
            return colors.count
        }
        if colorCount <= 12 {
            let diagnostic = XCTAttachment(string: """
            Distinct quantized RGB colors in the 32x32 card sample: \(colorCount), expected more than 12.
            App frame: \(appFrame); visible card frame: \(cardFrame).
            Screenshot pixels: \(image.width)x\(image.height); cropped pixel rect: \(cropRect).
            Media: \(app.buttons["mediaCard"].label)
            """)
            diagnostic.name = "media-card-color-diagnostics"
            diagnostic.lifetime = .keepAlways
            add(diagnostic)
            let crop = XCTAttachment(image: UIImage(cgImage: card))
            crop.name = "media-card-failed-pixels"
            crop.lifetime = .keepAlways
            add(crop)
        }
        XCTAssertGreaterThan(colorCount, 12, "The disposable media must display varied pixels, not a uniform-color card.")
    }
    private func queueItems(_ count: Int, category: String = "shuffle") {
        if category != "shuffle" {
            for _ in 0..<3 { if app.buttons[category].isHittable { break }; app.swipeUp() }
        }
        waitEnabled(category); app.buttons[category].tap()
        for _ in 0..<count { waitEnabled("deleteCard"); app.buttons["deleteCard"].tap() }
        app.buttons["closeSession"].tap()
        app.tabBars.buttons["Review"].tap()
        XCTAssertTrue(app.buttons["queueActions"].waitForExistence(timeout: 5))
    }

    func testPermissionDenied() {
        launch(authorize: false)
        XCTAssertTrue(app.buttons["requestAccess"].waitForExistence(timeout: 10))
        app.buttons["requestAccess"].tap()
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deny = system.buttons["Don’t Allow"]
        XCTAssertTrue(deny.waitForExistence(timeout: 10))
        deny.tap()
        XCTAssertTrue(app.buttons["Open Settings"].waitForExistence(timeout: 10))
        capture("permission-denied")
    }

    func testPermissionFull() {
        launch(authorize: false)
        XCTAssertTrue(app.buttons["requestAccess"].waitForExistence(timeout: 10))
        app.buttons["requestAccess"].tap()
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow Full Access"]
        XCTAssertTrue(allow.waitForExistence(timeout: 10)); allow.tap()
        XCTAssertTrue(app.buttons["shuffle"].waitForExistence(timeout: 10))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.staticTexts["Photo Access, Full Access"].waitForExistence(timeout: 5))
        capture("permission-full")
    }

    func testPermissionLimited() {
        launch(authorize: false)
        XCTAssertTrue(app.buttons["requestAccess"].waitForExistence(timeout: 10)); app.buttons["requestAccess"].tap()
        let limit = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Limit Access…"]
        XCTAssertTrue(limit.waitForExistence(timeout: 10)); limit.tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        capture("limited-picker")
        // The iOS 26 system picker exposes its thumbnail grid as remote elements.
        // Coordinates are within the verified iPhone 17 Pro picker, not the app's obscured List.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.17, dy: 0.45)).tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.91, dy: 0.165)).tap()
        XCTAssertTrue(app.buttons["Manage Selection"].waitForExistence(timeout: 10))
        let shuffle = app.buttons["shuffle"]
        XCTAssertTrue(shuffle.waitForExistence(timeout: 5))
        if XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: shuffle)], timeout: 3) != .completed {
            app.buttons["Manage Selection"].tap()
            XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.17, dy: 0.45)).tap()
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.91, dy: 0.165)).tap()
        }
        waitEnabled("shuffle"); capture("permission-limited")
        app.buttons["shuffle"].tap(); waitEnabled("keepCard")
        let progress = app.staticTexts["sessionProgress"].label
        // Resetting authorization retains iOS's prior limited selection.
        XCTAssertTrue(progress.hasPrefix("1 of "), progress)
        XCTAssertTrue(progress.contains("0 reviewed"), progress)
        app.buttons["closeSession"].tap()
        app.buttons["Manage Selection"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
    }

    func testEmptyLibraryAfterDeletingDisposableSamples() throws {
        launch(); waitEnabled("shuffle"); app.buttons["shuffle"].tap(); waitEnabled("deleteCard")
        let progress = app.staticTexts["sessionProgress"].label
        let count = Int(progress.components(separatedBy: " of ").last?.components(separatedBy: " ·").first ?? "") ?? 0
        try XCTSkipUnless(count > 0 && count <= 6, "Run this initial empty-library check before importing the fixture set.")
        for _ in 0..<count { waitEnabled("deleteCard"); app.buttons["deleteCard"].tap() }
        app.buttons["Review Queue"].tap()
        app.buttons["selectAll"].tap(); app.buttons["deleteSelected"].tap()
        app.buttons["Delete \(count) Items from Photos"].tap()
        let delete = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 10)); delete.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 10)); app.alerts.buttons["OK"].tap()
        app.tabBars.buttons["Clean"].tap()
        XCTAssertFalse(app.buttons["shuffle"].isEnabled)
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["No Accessible Media"].waitForExistence(timeout: 5)); capture("empty-library")
    }

    func testCoreSwipeUndoSkipAndResume() {
        launch(); waitEnabled("shuffle"); capture("clean")
        app.buttons["shuffle"].tap(); waitEnabled("keepCard"); capture("swipe")
        app.buttons["mediaCard"].swipeLeft()
        waitEnabled("keepCard")
        XCTAssertTrue(app.buttons["sessionQueue"].label.contains("1 items"))
        app.buttons["mediaCard"].swipeRight(); waitEnabled("keepCard")
        app.buttons["undo"].tap(); waitEnabled("keepCard")
        app.buttons["undo"].tap(); waitEnabled("keepCard")
        XCTAssertTrue(app.buttons["sessionQueue"].label.contains("0 items"))
        app.buttons["skip"].tap(); waitEnabled("keepCard")
        XCTAssertTrue(app.staticTexts["sessionProgress"].label.contains("0 reviewed"))
        app.buttons["undo"].tap(); waitEnabled("keepCard")
        app.buttons["deleteCard"].tap(); waitEnabled("keepCard")
        let progress = app.staticTexts["sessionProgress"].label
        app.buttons["closeSession"].tap()
        app.terminate(); launch(reset: false)
        XCTAssertTrue(app.buttons["continueSession"].waitForExistence(timeout: 10)); app.buttons["continueSession"].tap()
        waitEnabled("keepCard")
        XCTAssertEqual(app.staticTexts["sessionProgress"].label, progress)
        XCTAssertTrue(app.buttons["sessionQueue"].label.contains("1 items"))
        app.buttons["closeSession"].tap(); app.tabBars.buttons["Review"].tap()
        XCTAssertEqual(app.buttons.matching(identifier: "queueThumbnail").count, 1)
        capture("review")
        app.buttons["keepInstead"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Your Queue Is Clear"].waitForExistence(timeout: 5))
    }

    func testInspectionAndVideo() {
        launch()
        XCTAssertTrue(app.buttons["category-videos"].waitForExistence(timeout: 10)); app.buttons["category-videos"].tap()
        waitEnabled("playVideo"); app.buttons["playVideo"].tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Pause"), object: app.buttons["playVideo"])], timeout: 2), .completed)
        app.buttons["Unmute"].tap()
        app.buttons["inspect"].tap()
        XCTAssertTrue(app.buttons["closeInspection"].waitForExistence(timeout: 5))
        capture("video-inspection")
        app.buttons["closeInspection"].tap()
        XCTAssertEqual(app.buttons["playVideo"].label, "Play")
        app.buttons["closeSession"].tap()
        app.buttons["shuffle"].tap(); waitEnabled("inspect")
        let progress = app.staticTexts["sessionProgress"].label
        app.buttons["inspect"].tap()
        XCTAssertTrue(app.buttons["closeInspection"].waitForExistence(timeout: 5))
        app.swipeLeft(); app.swipeRight()
        app.buttons["closeInspection"].tap()
        XCTAssertEqual(app.staticTexts["sessionProgress"].label, progress)
    }

    func testSelectAllDoesNotOpenPhoto() {
        launch(); waitEnabled("shuffle"); app.buttons["shuffle"].tap(); waitEnabled("deleteCard")
        let progress = app.staticTexts["sessionProgress"].label
        let count = Int(progress.components(separatedBy: " of ").last?.components(separatedBy: " ·").first ?? "") ?? 0
        XCTAssertGreaterThan(count, 0)
        for _ in 0..<count { waitEnabled("deleteCard"); app.buttons["deleteCard"].tap() }
        app.buttons["Review Queue"].tap()
        let selectAll = app.buttons["selectAll"]
        XCTAssertTrue(selectAll.waitForExistence(timeout: 5))
        selectAll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertFalse(app.buttons["closeInspection"].exists)
        XCTAssertEqual(app.staticTexts["selectionCount"].label, "\(count) selected")
        XCTAssertEqual(selectAll.label, "Deselect All")
        XCTAssertTrue(app.buttons["deleteSelected"].isEnabled)

        selectAll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertEqual(app.staticTexts["selectionCount"].label, "0 selected")
        XCTAssertFalse(app.buttons["deleteSelected"].isEnabled)

        app.buttons["queueThumbnail"].firstMatch.tap()
        XCTAssertTrue(app.buttons["closeInspection"].waitForExistence(timeout: 5))
        app.buttons["closeInspection"].tap()
        XCTAssertEqual(app.staticTexts["selectionCount"].label, "0 selected")
    }

    func testQueueClearAndDeletionCancel() {
        launch(); queueItems(3)
        app.buttons["selectQueueItem"].firstMatch.tap()
        XCTAssertEqual(app.staticTexts["selectionCount"].label, "1 selected")
        app.buttons["deleteSelected"].tap()
        app.buttons["Cancel"].tap()
        XCTAssertEqual(app.buttons.matching(identifier: "queueThumbnail").count, 3)
        app.buttons["deleteSelected"].tap()
        app.buttons["Delete 1 Item from Photos"].tap()
        let systemCancel = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Don’t Allow"]
        XCTAssertTrue(systemCancel.waitForExistence(timeout: 10)); systemCancel.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 10)); capture("delete-cancelled")
        app.alerts.buttons["OK"].tap()
        XCTAssertEqual(app.buttons.matching(identifier: "queueThumbnail").count, 3)
        app.buttons["queueActions"].tap(); app.buttons["Clear Queue"].tap()
        app.buttons["Clear Queue"].tap()
        XCTAssertTrue(app.staticTexts["Your Queue Is Clear"].waitForExistence(timeout: 5))
    }

    func testDeletionFailurePreservesQueue() {
        launch(extra: ["--simulate-delete-failure"]); queueItems(2)
        app.buttons["selectAll"].tap(); app.buttons["deleteSelected"].tap()
        app.buttons["Delete 2 Items from Photos"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.staticTexts.element(boundBy: 1).label.contains("queue is unchanged"))
        app.alerts.buttons["OK"].tap()
        XCTAssertEqual(app.buttons.matching(identifier: "queueThumbnail").count, 2)
    }

    func testActualSelectedDeletion() {
        launch(); queueItems(3, category: "category-older")
        app.buttons["selectQueueItem"].firstMatch.tap()
        app.buttons["deleteSelected"].tap(); app.buttons["Delete 1 Item from Photos"].tap()
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let delete = system.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 10)); delete.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 10)); capture("deleted-one-item")
        app.alerts.buttons["OK"].tap()
        XCTAssertEqual(app.buttons.matching(identifier: "queueThumbnail").count, 2)
    }

    func testCancelledAndVerticalDragsKeepProgress() {
        launch(); app.buttons["shuffle"].tap(); waitEnabled("keepCard")
        let before = app.staticTexts["sessionProgress"].label
        let card = app.buttons["mediaCard"]
        let center = card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.press(forDuration: 0.1, thenDragTo: card.coordinate(withNormalizedOffset: CGVector(dx: 0.58, dy: 0.5)), withVelocity: .slow, thenHoldForDuration: 0.2)
        XCTAssertEqual(app.staticTexts["sessionProgress"].label, before)
        card.swipeUp()
        XCTAssertEqual(app.staticTexts["sessionProgress"].label, before)
        XCTAssertTrue(app.buttons["deleteCard"].isEnabled)
    }

    func testImageZoomAndEmptyCategoryPreservesSession() {
        launch(); app.buttons["shuffle"].tap(); waitEnabled("keepCard")
        let progress = app.staticTexts["sessionProgress"].label
        app.buttons["closeSession"].tap()
        app.buttons["category-screenshots"].tap()
        XCTAssertTrue(app.staticTexts["No Screenshots to Review"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.buttons["continueSession"].tap(); waitEnabled("keepCard")
        XCTAssertEqual(app.staticTexts["sessionProgress"].label, progress)
        app.buttons["closeSession"].tap()
        for _ in 0..<3 { if app.buttons["category-older"].isHittable { break }; app.swipeUp() }
        app.buttons["category-older"].tap(); waitEnabled("inspect")
        let imageProgress = app.staticTexts["sessionProgress"].label
        app.buttons["inspect"].tap(); XCTAssertTrue(app.buttons["closeInspection"].waitForExistence(timeout: 5))
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        scroll.pinch(withScale: 2, velocity: 1)
        scroll.swipeLeft(); capture("zoomed-image")
        app.buttons["closeInspection"].tap(); waitEnabled("keepCard")
        XCTAssertEqual(app.staticTexts["sessionProgress"].label, imageProgress)
    }

    func testAppearanceAndLargeText() throws {
        launch(); waitEnabled("shuffle"); capture("appearance-clean")
        app.buttons["shuffle"].tap(); waitEnabled("keepCard"); capture("appearance-swipe")
        try assertMediaCardHasVariedPixels()
        XCTAssertTrue(app.buttons["keepCard"].isHittable)
        XCTAssertTrue(app.buttons["deleteCard"].isHittable)
        XCTAssertTrue(app.buttons["skip"].isHittable)
        app.buttons["deleteCard"].tap(); waitEnabled("keepCard")
        app.buttons["closeSession"].tap(); app.tabBars.buttons["Review"].tap()
        let keepInstead = app.buttons["keepInstead"].firstMatch
        XCTAssertTrue(keepInstead.waitForExistence(timeout: 5))
        for _ in 0..<4 { if keepInstead.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(keepInstead.isHittable)
        capture("appearance-review")
    }

    func testRapidConsecutiveSwipes() {
        launch(); app.buttons["shuffle"].tap(); waitEnabled("keepCard")
        for _ in 0..<5 { app.buttons["mediaCard"].swipeLeft(velocity: .fast) }
        let progress = app.staticTexts["sessionProgress"].label
        let reviewed = Int(progress.components(separatedBy: " · ").last?.components(separatedBy: " ").first ?? "") ?? -1
        XCTAssertEqual(reviewed, 5)
        XCTAssertTrue(app.buttons["sessionQueue"].label.contains("5 items"))
        for _ in 0..<5 { app.buttons["undo"].tap() }
        XCTAssertTrue(app.staticTexts["sessionProgress"].label.contains("0 reviewed"))
        XCTAssertTrue(app.buttons["sessionQueue"].label.contains("0 items"))
        capture("rapid-swipes-restored")
    }

    func testRapidButtonsAndAccessibleAlternatives() {
        launch(); app.buttons["shuffle"].tap(); waitEnabled("keepCard")
        for _ in 0..<5 { waitEnabled("keepCard"); app.buttons["keepCard"].tap() }
        waitEnabled("keepCard")
        XCTAssertTrue(app.staticTexts["sessionProgress"].label.contains("5 reviewed"))
        for _ in 0..<5 { app.buttons["undo"].tap(); waitEnabled("keepCard") }
        XCTAssertTrue(app.staticTexts["sessionProgress"].label.contains("0 reviewed"))
        XCTAssertFalse(app.buttons["undo"].isEnabled)
        XCTAssertTrue(app.buttons["skip"].isHittable)
        XCTAssertTrue(app.buttons["deleteCard"].isHittable)
        capture("accessible-controls")
    }

    func testCompletedSessionCanResumeAndUndo() {
        launch()
        waitEnabled("category-videos")
        app.buttons["category-videos"].tap()
        waitEnabled("keepCard")
        let originalProgress = app.staticTexts["sessionProgress"].label
        let originalMedia = app.buttons["mediaCard"].label
        XCTAssertTrue(originalProgress.hasPrefix("1 of 1"), "This test requires the single disposable video fixture.")

        app.buttons["keepCard"].tap()
        XCTAssertTrue(app.buttons["Undo Last Decision"].waitForExistence(timeout: 5))
        app.buttons["Back to Clean"].tap()
        XCTAssertTrue(app.buttons["continueSession"].waitForExistence(timeout: 5))
        app.terminate()
        launch(reset: false)

        waitEnabled("continueSession")
        app.buttons["continueSession"].tap()
        waitEnabled("Undo Last Decision")
        app.buttons["Undo Last Decision"].tap()
        waitEnabled("keepCard")
        XCTAssertEqual(app.staticTexts["sessionProgress"].label, originalProgress)
        XCTAssertEqual(app.buttons["mediaCard"].label, originalMedia)
        XCTAssertTrue(app.buttons["playVideo"].exists)
        capture("completed-session-undo-restored")
    }

    func testReducedMotionAndTransparency() {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        for _ in 0..<5 {
            if settings.navigationBars["Settings"].exists { break }
            guard settings.navigationBars.buttons.firstMatch.exists else { break }
            settings.navigationBars.buttons.firstMatch.tap()
        }

        func openRow(_ title: String) {
            let row = settings.staticTexts[title].firstMatch
            for _ in 0..<4 {
                if row.isHittable { break }
                settings.swipeUp()
            }
            XCTAssertTrue(row.waitForExistence(timeout: 5), settings.debugDescription)
            row.tap()
        }
        func toggle(_ title: String, on: Bool) {
            let control = settings.switches[title].firstMatch
            for _ in 0..<4 {
                if control.isHittable { break }
                settings.swipeUp()
            }
            XCTAssertTrue(control.waitForExistence(timeout: 5), settings.debugDescription)
            if (control.value as? String == "1") != on {
                control.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value == %@", on ? "1" : "0"), object: control
            )], timeout: 5), .completed)
        }
        func settingsCapture(_ name: String) {
            let attachment = XCTAttachment(screenshot: settings.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        openRow("Accessibility")
        openRow("Motion")
        toggle("Reduce Motion", on: true)
        settingsCapture("reduce-motion-enabled")
        settings.navigationBars.buttons.firstMatch.tap()
        openRow("Display & Text Size")
        toggle("Reduce Transparency", on: true)
        settingsCapture("reduce-transparency-enabled")

        launch(); app.buttons["shuffle"].tap(); waitEnabled("keepCard")
        let before = app.staticTexts["sessionProgress"].label
        app.buttons["mediaCard"].swipeLeft(); waitEnabled("keepCard")
        app.buttons["undo"].tap(); waitEnabled("keepCard")
        XCTAssertEqual(app.staticTexts["sessionProgress"].label, before)
        XCTAssertTrue(app.buttons["deleteCard"].isHittable)
        XCTAssertTrue(app.buttons["keepCard"].isHittable)
        capture("reduced-motion-transparency-swipe")
        app.buttons["closeSession"].tap()

        settings.activate()
        toggle("Reduce Transparency", on: false)
        settings.navigationBars.buttons.firstMatch.tap()
        openRow("Motion")
        toggle("Reduce Motion", on: false)
        settings.navigationBars.buttons.firstMatch.tap()
        settings.navigationBars.buttons.firstMatch.tap()
        app.activate()
    }

    func testPlacesStartsMetadataGroup() {
        launch()
        for _ in 0..<3 {
            if app.buttons["category-places"].isHittable { break }
            app.swipeUp()
        }
        waitEnabled("category-places")
        app.buttons["category-places"].tap()
        let groups = app.buttons.matching(identifier: "placeGroup")
        let selectedTitle = "Near 36.2, -116.9°"
        let selectedGroup = groups.matching(NSPredicate(format: "label BEGINSWITH %@", selectedTitle)).firstMatch
        let otherGroup = groups.matching(NSPredicate(format: "label BEGINSWITH %@", "Near 46.5, 7.9°")).firstMatch
        XCTAssertTrue(selectedGroup.waitForExistence(timeout: 10))
        XCTAssertTrue(otherGroup.waitForExistence(timeout: 5))
        XCTAssertEqual(groups.count, 2)
        let count = Int((selectedGroup.value as? String)?.components(separatedBy: " ").first ?? "") ?? 0
        XCTAssertGreaterThan(count, 0)

        selectedGroup.tap()
        waitEnabled("keepCard")
        XCTAssertTrue(app.navigationBars[selectedTitle].exists)
        XCTAssertEqual(app.staticTexts["sessionProgress"].label, "1 of \(count) · 0 reviewed")
        capture("places-metadata-session")
        app.buttons["closeSession"].tap()
        XCTAssertTrue(app.navigationBars["Places"].waitForExistence(timeout: 5))
    }
}
