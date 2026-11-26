import XCTest

/// Build 19 checks for the owner's Build 18 findings with large text (team 06). Each test catches one fault class:
/// - tile titles broken inside a word ("Sau-er-stoff", "An-span-nung") and numbers or units cut off ("14…"),
/// - explanation sentences on the screen (replaced by ⓘ popovers, team 02),
/// - content under the header bar while the screen rests at the top.
/// Tiles speak as one element, so their text layout comes from the test-only probe (`-qaProbe YES`, `M1.Probe`).
/// Runs in the logic-and-ui shard; the AX3 audits are in AccessibilityTests.
@MainActor
final class LargeTextTests: XCTestCase {
    /// `xxxl` = accessibility3 (the screenshot matrix), `ax5` = the largest size.
    static let largeSizes = ["xxxl", "ax5"]

    override func setUp() async throws {
        continueAfterFailure = true
    }

    // MARK: Tile titles and numbers

    func testTileTextAtLargeSizes() throws {
        for size in Self.largeSizes {
            try checkTiles(dynamicType: size)
        }
    }

    private func checkTiles(dynamicType: String) throws {
        let app = M1.launch(dynamicType: dynamicType, extraArguments: M1.Probe.launchArguments)
        defer { app.terminate() }
        try M1.skipIfMissing { try M1.require(app, M1.Screen.dashboard, step: "Dashboard", timeout: 30) }
        Thread.sleep(forTimeInterval: 1.5)
        M1.attachScreenshot(self, name: "largeText__\(dynamicType)__dashboard")

        // Scroll through the whole list: every tile reports once it has been laid out, and reports are kept.
        var reports = M1.probe(app)
        guard !reports.isEmpty else {
            return missingProbe("Kacheln (\(dynamicType))", detail: "qa.probe fehlt oder ist leer")
        }
        var unchanged = 0
        for _ in 0..<16 where unchanged < 2 {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.4)
            let now = M1.probe(app)
            unchanged = now.count == reports.count ? unchanged + 1 : 0
            reports = now
        }

        let titles = reports.filter { $0.key.hasPrefix("tile.title.") }
        XCTAssertGreaterThanOrEqual(titles.count, 3, "\(dynamicType): nur \(titles.count) Kacheltitel gemeldet: \(titles.keys.sorted())")
        var lines: [String] = []
        for (id, value) in reports.sorted(by: { $0.key < $1.key }) where id.hasPrefix("tile.") {
            guard let layout = TextLayout(value) else {
                XCTFail("\(dynamicType): \(id) unlesbar: \(value)"); continue
            }
            let name = id.split(separator: ".", maxSplits: 2).last.map(String.init) ?? id
            lines.append("\(id)=\(value)")
            if id.hasPrefix("tile.title.") {
                // More lines than words means a word was split across lines (hyphenation).
                XCTAssertLessThanOrEqual(layout.lines, max(layout.words, 1),
                                         "\(dynamicType): Kacheltitel „\(name)“ mit Silbentrennung (\(value))")
                XCTAssertTrue(layout.fits, "\(dynamicType): Kacheltitel „\(name)“ abgeschnitten (\(value))")
            } else {
                // Number and unit stay on one line and whole (scaling down to 60 % is allowed, "14…" is not).
                XCTAssertEqual(layout.lines, 1, "\(dynamicType): \(id) bricht um (\(value))")
                XCTAssertTrue(layout.fits, "\(dynamicType): \(id) abgeschnitten (\(value))")
            }
        }
        attachText(lines.joined(separator: "\n"), name: "largeText__\(dynamicType)__tiles.txt")
        // Also in the job log: the result bundle is not always reachable.
        print("LARGETEXT[\(dynamicType)] " + lines.joined(separator: " ; "))
    }

    // MARK: Axes
    // `testTimelineAxesLabelled` follows with team 03's axis reports (part 2, after Build 19 charts).

    // MARK: No explanation texts

    func testNoExplanationTexts() throws {
        // The Verlauf joins in part 2 with team 03's Build 19 charts (its old hint sentence goes then).
        for place in [M1.Place.dashboard] {
            let app = M1.launch()
            defer { app.terminate() }
            try M1.skipIfMissing {
                // `.timeline` opens a cursor read-out; the plain timeline is what a person sees first.
                if place == .timeline {
                    try M1.require(app, M1.Screen.dashboard, step: "Dashboard", timeout: 30)
                    let tile = try M1.require(app, M1.Dashboard.heartRateTile, step: "Puls-Kachel")
                    M1.reveal(tile, in: app)
                    tile.tap()
                    try M1.require(app, M1.Timeline.chart, step: "Spuren")
                } else {
                    try M1.open(place, in: app)
                }
            }
            Thread.sleep(forTimeInterval: 1)
            let screenID = place == .dashboard ? M1.Screen.dashboard : M1.Screen.timeline
            var found: [String] = []
            for _ in 0..<6 {
                found += explanationTexts(in: app, screen: screenID).filter { !found.contains($0) }
                app.swipeUp()
            }
            XCTAssertTrue(found.isEmpty, "\(place.rawValue): Erklärtexte statt ⓘ: \(found)")
        }
    }

    /// Ids whose text is ROOK's own statement or a read-out the person asked for, not an explanation.
    static let explanationAllowed = ["testBanner", "rook.", "why.", "timeline.selection", "hypnogram.selection"]
    /// A text with this many words of running text (`proseWords`) is an explanation; titles, values, data lines and
    /// short hints have fewer.
    static let explanationWords = 9
    /// Unit and label abbreviations that appear in data lines, not in sentences.
    static let unitWords: Set<String> = ["min", "bpm", "kcal", "std", "rem", "hrv", "spo", "km", "ms"]

    /// Words of running text: letters only, at least 3 of them, no unit. A data line such as
    /// "8 h Schlaf · 22:40–06:55 · Tief 2 h 10 min · REM 1 h 40 min" has 2, the old hint
    /// "Tippe auf die Spuren oder halte und ziehe, um jeden Messpunkt mit Uhrzeit zu sehen." has 13.
    static func proseWords(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0 == "·" }).filter { token in
            let word = token.trimmingCharacters(in: .punctuationCharacters.union(.symbols))
            return word.count >= 3 && word.allSatisfy(\.isLetter) && !unitWords.contains(word.lowercased())
        }.count
    }

    private func explanationTexts(in app: XCUIApplication, screen: String) -> [String] {
        let root = M1.element(app, screen)
        guard root.exists, let snapshot = try? root.snapshot() else { return [] }
        var allowedFrames: [CGRect] = []
        var texts: [(label: String, id: String, frame: CGRect)] = []
        func walk(_ node: any XCUIElementSnapshot) {
            if Self.explanationAllowed.contains(where: { node.identifier.hasPrefix($0) }) {
                allowedFrames.append(node.frame)
            }
            if node.elementType == .staticText { texts.append((node.label, node.identifier, node.frame)) }
            node.children.forEach(walk)
        }
        walk(snapshot)
        return texts.compactMap { text in
            guard Self.proseWords(text.label) >= Self.explanationWords else { return nil }
            if Self.explanationAllowed.contains(where: { text.id.hasPrefix($0) }) { return nil }
            // Texts inside the ROOK card or a read-out (no own id).
            if allowedFrames.contains(where: { $0.insetBy(dx: -1, dy: -1).contains(text.frame) }) { return nil }
            return text.label
        }
    }

    // MARK: Header covers nothing

    /// While the screen rests at the top, no content may start under the header bar (title and buttons). Large text
    /// makes the header taller, so this runs at every large size. Scrolled states are in the screenshot matrix
    /// (`dashboardScrolled`, `timelineScrolled`) for the visual review.
    func testHeaderCoversNothingAtRest() throws {
        for size in ["default"] + Self.largeSizes {
            for place in [M1.Place.dashboard, .timeline] {
                let app = M1.launch(dynamicType: size)
                defer { app.terminate() }
                try M1.skipIfMissing {
                    try M1.require(app, M1.Screen.dashboard, step: "Dashboard", timeout: 30)
                    if place == .timeline {
                        app.tabBars.buttons[M1.tabTimeline].tap()
                        try M1.require(app, M1.Screen.timeline, step: "Verlauf")
                    }
                }
                Thread.sleep(forTimeInterval: 1.5)
                let screenID = place == .dashboard ? M1.Screen.dashboard : M1.Screen.timeline
                let bar = app.navigationBars.firstMatch
                guard bar.exists, let root = try? M1.element(app, screenID).snapshot() else {
                    XCTFail("\(size)/\(place.rawValue): Kopfleiste oder Bildschirm fehlt"); continue
                }
                let barBottom = bar.frame.maxY
                var covered: [String] = []
                func walk(_ node: any XCUIElementSnapshot) {
                    let frame = node.frame
                    let isContent = !frame.isEmpty && node.elementType != .other && node.elementType != .scrollView
                    if isContent, frame.minY < barBottom - 1, frame.maxY > 0 {
                        covered.append("\(node.identifier.isEmpty ? node.label : node.identifier) (y \(Int(frame.minY)))")
                    }
                    node.children.forEach(walk)
                }
                walk(root)
                if !covered.isEmpty {
                    M1.attachScreenshot(self, name: "largeText__\(size)__\(place.rawValue)__header")
                }
                XCTAssertTrue(covered.isEmpty,
                              "\(size)/\(place.rawValue): unter der Kopfleiste (bis y \(Int(barBottom))): \(covered)")
            }
        }
    }

    // MARK: Helpers

    /// A probe or report that is not wired yet: skip until integrated, failure in strict mode.
    private func missingProbe(_ what: String, detail: String) {
        let message = "\(what): \(detail)"
        if M1.strict { XCTFail(message) } else { XCTExpectFailure("Noch nicht integriert") { XCTFail(message) } }
    }

    private func attachText(_ text: String, name: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// `lines:N,words:W,fits:1|0` from `qaTextProbe`.
struct TextLayout {
    let lines: Int
    let words: Int
    let fits: Bool

    init?(_ report: String) {
        var fields: [String: Int] = [:]
        for pair in report.split(separator: ",") {
            let parts = pair.split(separator: ":")
            if parts.count == 2, let number = Int(parts[1]) { fields[String(parts[0])] = number }
        }
        guard let lines = fields["lines"], let words = fields["words"], let fits = fields["fits"] else { return nil }
        self.lines = lines
        self.words = words
        self.fits = fits == 1
    }
}
