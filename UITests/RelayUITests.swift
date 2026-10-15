import XCTest

@MainActor
final class RelayUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTransferCanPauseResumeAndReset() {
        let app = launchApp()
        let send = app.buttons["send"]
        assertLabel(send, beginsWith: "Send a packet burst")

        send.tap()
        assertLabel(send, beginsWith: "Pause transfer")

        send.tap()
        assertLabel(send, beginsWith: "Resume transfer")

        send.tap()
        assertLabel(send, beginsWith: "Pause transfer")

        app.buttons["reset"].tap()
        assertLabel(send, beginsWith: "Send a packet burst")
        let ready = app.staticTexts.matching(NSPredicate(format: "label == %@", "Ready to send")).firstMatch
        XCTAssertTrue(ready.waitForExistence(timeout: 5), "Reset should clear the current journey.")
    }

    func testUDPSelectionUpdatesPacketTrace() {
        let app = launchApp()
        let udp = app.buttons["protocol-udp"]
        reveal(udp, in: app)
        udp.tap()
        XCTAssertTrue(udp.isSelected, "The protocol picker should reflect the selected transport.")

        let trace = app.buttons["packetTrace"]
        reveal(trace, in: app)
        trace.tap()
        XCTAssertTrue(app.navigationBars["Packet journey"].waitForExistence(timeout: 5))

        let udpExplanation = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Raw UDP delivers")
        ).firstMatch
        XCTAssertTrue(udpExplanation.waitForExistence(timeout: 5), "The trace should explain the selected protocol's delivery behavior.")
        XCTAssertTrue(udpExplanation.label.contains("Missing datagrams remain missing"))

        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["tune"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Packet journey"].exists)
    }

    func testLatencyUpdatesReadoutAndDefaultsRestoreIt() {
        let app = launchApp()
        let roundTrip = roundTripReadout(in: app)
        XCTAssertTrue(roundTrip.waitForExistence(timeout: 5))
        let defaultRoundTrip = roundTrip.label

        app.buttons["tune"].tap()
        XCTAssertTrue(app.navigationBars["Tune the network"].waitForExistence(timeout: 5))
        let latency = app.sliders["latencySlider"]
        reveal(latency, in: app)
        let latencyValue = app.staticTexts["latencySliderValue"]
        XCTAssertTrue(latencyValue.waitForExistence(timeout: 5))
        let defaultLatency = latencyValue.label

        latency.adjust(toNormalizedSliderPosition: 0.85)
        waitForLabelChange(latencyValue, from: defaultLatency)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["tune"].waitForExistence(timeout: 5))
        waitForLabelChange(roundTripReadout(in: app), from: defaultRoundTrip)

        app.buttons["tune"].tap()
        XCTAssertTrue(app.navigationBars["Tune the network"].waitForExistence(timeout: 5))
        let restore = app.buttons["defaultNetwork"]
        reveal(restore, in: app)
        restore.tap()
        let restoredLatency = app.staticTexts["latencySliderValue"]
        let restored = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", defaultLatency), object: restoredLatency
        )
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed)

        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["tune"].waitForExistence(timeout: 5))
        let restoredRoundTrip = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", defaultRoundTrip), object: roundTripReadout(in: app)
        )
        XCTAssertEqual(XCTWaiter.wait(for: [restoredRoundTrip], timeout: 5), .completed,
                       "Restoring network defaults should restore the original round-trip estimate.")
    }

    func testBellLabsArchivePreservesNetworkAndLeavesSendUsable() {
        let app = launchApp()
        let roundTrip = roundTripReadout(in: app)
        XCTAssertTrue(roundTrip.waitForExistence(timeout: 5))
        let initialRoundTrip = roundTrip.label
        let source = app.buttons["sourcePicker"]
        let destination = app.buttons["destinationPicker"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
        let initialSource = source.label
        let initialDestination = destination.label

        let seal = app.buttons["bellLabsSeal"]
        reveal(seal, in: app)
        seal.tap()
        let memo = app.descendants(matching: .any).matching(identifier: "bellLabsMemo").firstMatch
        XCTAssertTrue(memo.waitForExistence(timeout: 5), "The 1984 seal should open the archive.")
        let count = app.staticTexts["babyBellCount"]
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        XCTAssertEqual(count.label, "7 regional companies")
        attachScreenshot("Bell Labs archive", in: app)

        let pacificTelesis = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Pacific Telesis")
        ).firstMatch
        reveal(pacificTelesis, in: app)
        XCTAssertTrue(pacificTelesis.exists, "The archive should include the original regional companies.")
        attachScreenshot("Archive regional directory", in: app)

        let done = app.buttons["bellLabsMemoDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        XCTAssertTrue(seal.waitForExistence(timeout: 5))
        XCTAssertFalse(memo.exists)
        XCTAssertEqual(roundTripReadout(in: app).label, initialRoundTrip,
                       "The historical decoration must not alter the network model.")
        XCTAssertEqual(source.label, initialSource)
        XCTAssertEqual(destination.label, initialDestination)
        attachScreenshot("Main with Baby Bells", in: app)

        let send = app.buttons["send"]
        send.tap()
        assertLabel(send, beginsWith: "Pause transfer")
        app.buttons["reset"].tap()
        assertLabel(send, beginsWith: "Send a packet burst")
    }

    func testSimulatedSnifferDecodesPacketsAndKeepsNetworkEditsLocal() {
        let app = launchApp()
        let roundTrip = roundTripReadout(in: app)
        XCTAssertTrue(roundTrip.waitForExistence(timeout: 5))
        let initialRoundTrip = roundTrip.label
        let sniff = app.buttons["sniff"]
        reveal(sniff, in: app)
        sniff.tap()
        XCTAssertTrue(app.navigationBars["Packet sniffer"].waitForExistence(timeout: 5))

        let busy = app.buttons["sniffPresetBusy"]
        reveal(busy, in: app)
        busy.tap()
        let start = app.buttons["sniffStart"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        let status = app.staticTexts["snifferStatus"]
        assertLabel(status, beginsWith: "Capturing simulated traffic")
        let viewPackets = app.buttons["sniffViewPackets"]
        XCTAssertTrue(viewPackets.waitForExistence(timeout: 5))
        XCTAssertTrue(viewPackets.isEnabled)
        viewPackets.tap()
        attachScreenshot("Live packet buffer", in: app)
        let finished = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label BEGINSWITH %@", "Probe complete"), object: status
        )
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 25), .completed,
                       "The bounded simulated probe should finish without a real network connection.")

        // Jump directly to the lazy packet buffer after completion.
        viewPackets.tap()
        let packetRows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "sniffCaptureRow-"))
        let firstPacket = packetRows.firstMatch
        XCTAssertTrue(firstPacket.waitForExistence(timeout: 5))
        let rowVisible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == YES"), object: firstPacket)
        XCTAssertEqual(XCTWaiter.wait(for: [rowVisible], timeout: 5), .completed,
                       "The packet jump should expose an inspectable row without blind scrolling.")
        attachScreenshot("Completed packet buffer", in: app)
        firstPacket.tap()
        let sourceAddress = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "192.0.2.")
        ).firstMatch
        let destinationAddress = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "198.51.100.")
        ).firstMatch
        XCTAssertTrue(sourceAddress.waitForExistence(timeout: 5), "The decoder should expose a documentation IPv4 source.")
        XCTAssertTrue(destinationAddress.waitForExistence(timeout: 5), "The decoder should expose a documentation IPv4 destination.")
        reveal(destinationAddress, in: app)
        attachScreenshot("Packet decoder and documentation addresses", in: app)
        app.buttons["snifferDecodeDone"].tap()

        let clean = app.buttons["sniffPresetClean"]
        for _ in 0..<7 where !clean.isHittable {
            guard let scroll = app.scrollViews.allElementsBoundByIndex.reversed().first(where: { $0.isHittable }) else { break }
            scroll.swipeDown()
        }
        // The preset is above the buffer. Never fall back to reveal(), which
        // scrolls only upward and could move farther away from this control.
        XCTAssertTrue(clean.waitForExistence(timeout: 5))
        XCTAssertTrue(clean.isHittable, "Scrolling back toward the top should reveal the Clean preset.")
        clean.tap()
        assertLabel(status, beginsWith: "Network changed")
        assertLabel(start, beginsWith: "Start new capture")
        let cleared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == NO"), object: packetRows.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [cleared], timeout: 5), .completed,
                       "Changing probe conditions should clear the previous capture buffer.")

        app.buttons["snifferDone"].tap()
        XCTAssertTrue(sniff.waitForExistence(timeout: 5))
        XCTAssertEqual(roundTripReadout(in: app).label, initialRoundTrip,
                       "Sniffer conditions must not alter the playground's network configuration.")
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["send"].waitForExistence(timeout: 10))
        attachScreenshot("Main startup", in: app)
        return app
    }

    private func attachScreenshot(_ title: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = title
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertLabel(_ element: XCUIElement, beginsWith prefix: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), file: file, line: line)
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label BEGINSWITH %@", prefix), object: element
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed,
                       "Expected '\(prefix)', found '\(element.label)'.", file: file, line: line)
    }

    private func waitForLabelChange(_ element: XCUIElement, from previous: String,
                                   file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), file: file, line: line)
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@", previous), object: element
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed,
                       "The displayed metric should change after changing latency.", file: file, line: line)
    }

    private func roundTripReadout(in app: XCUIApplication) -> XCUIElement {
        let identified = app.descendants(matching: .any).matching(identifier: "roundTripReadout").firstMatch
        if identified.exists { return identified }
        return app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@ AND label != %@", "ROUND TRIP", "ROUND TRIP")
        ).firstMatch
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication,
                        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), file: file, line: line)
        for _ in 0..<7 where !element.isHittable {
            let scrollView = app.scrollViews.allElementsBoundByIndex.reversed().first { $0.isHittable }
            guard let scrollView else {
                XCTFail("No visible scroll view can reveal the control.", file: file, line: line)
                return
            }
            scrollView.swipeUp()
        }
        XCTAssertTrue(element.isHittable, "The control should be available to interact with.", file: file, line: line)
    }
}
