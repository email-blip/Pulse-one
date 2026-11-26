import XCTest

/// MetricTile with long values at large text (team 02). The `designKit` scenario shows "123.456 Schritte" in a wide
/// tile and "12.345 kcal" in a large one; at every large size each title, number and unit must stay on one line and
/// whole (scaling to the probe's floor is fine, "14…" is not). Same probe and rules as team 06's LargeTextTests, but
/// with fixed values, so a growing step count in the M1 scenario cannot hide or cause a failure.
@MainActor
final class DesignKitLargeTextTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = true
    }

    func testLongTileValuesStayWhole() throws {
        for size in ["large3", "xxxl", "ax5"] {
            let app = M1.launch("designKit", dynamicType: size, extraArguments: M1.Probe.launchArguments)
            XCTAssertTrue(app.descendants(matching: .any)["screen.designKit"].waitForExistence(timeout: 30),
                          "\(size): DesignKit-Vorschau fehlt")
            Thread.sleep(forTimeInterval: 1)
            var reports = M1.probe(app)
            var unchanged = 0
            for _ in 0..<16 where unchanged < 2 {
                app.swipeUp()
                Thread.sleep(forTimeInterval: 0.4)
                let now = M1.probe(app)
                unchanged = now.count == reports.count ? unchanged + 1 : 0
                reports = now
            }
            for id in ["tile.value.Schritte", "tile.unit.Schritte", "tile.value.Energie", "tile.unit.Energie"] {
                guard let report = reports[id], let layout = TextLayout(report) else {
                    XCTFail("\(size): \(id) nicht gemeldet (\(reports.keys.sorted()))"); continue
                }
                XCTAssertEqual(layout.lines, 1, "\(size): \(id) bricht um (\(report))")
                XCTAssertTrue(layout.fits, "\(size): \(id) abgeschnitten (\(report))")
            }
            for (id, report) in reports where id.hasPrefix("tile.title.") {
                guard let layout = TextLayout(report) else { XCTFail("\(size): \(id) unlesbar: \(report)"); continue }
                XCTAssertLessThanOrEqual(layout.lines, max(layout.words, 1), "\(size): \(id) getrennt (\(report))")
                XCTAssertTrue(layout.fits, "\(size): \(id) abgeschnitten (\(report))")
            }
            app.terminate()
        }
    }
}
