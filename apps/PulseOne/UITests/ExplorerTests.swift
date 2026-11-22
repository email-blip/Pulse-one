import XCTest

/// Automatic walkthrough ("KI-Rundgang", DECISIONS.md 2026-11-22): starts every area of the app with its test
/// data, taps every button it can safely reach, follows the screens they open one level deeper and checks each
/// new screen. Nobody has to write a test per button, so new screens are covered as soon as they exist.
///
/// Blocking (the run turns red): the app crashes after a tap, a screen shows broken text (Optional(…), nan,
/// format placeholders, debug text) or fails the accessibility audit.
/// Reported only (explore-report.md on the ci-screenshots branch): buttons without visible reaction, text that
/// runs off the screen, buttons skipped on purpose, screens not reached in the time budget.
///
/// Not covered here (hand tests): the real ring over Bluetooth, real Apple Health data, system permission
/// dialogs, notifications and the alarm.
@MainActor
final class ExplorerTests: XCTestCase {
    /// Start points: each area opens on its own tab with its test data.
    static let starts = ["today", "health", "intelligence", "coach", "nutrition", "companion", "profile", "devices"]
    /// Total wall-clock budget. The accessibility shard has about this much room next to the slowest shard.
    static let budget: TimeInterval = 11 * 60
    /// Root screen = depth 0. Screens at maxDepth are checked and photographed, their buttons are not tapped.
    static let maxDepth = 2
    static let maxPages = 4
    static let maxAuditsPerStart = 3

    /// Buttons that would leave the test sandbox (permissions, share sheet, camera, Bluetooth) or destroy the
    /// state the walk depends on. Matched case-insensitively against identifier and label.
    static let skipped = ["lösch", "delete", "entfern", "zurücksetzen", "wiederherstellen", "verwerfen", "leeren",
                          "ausschalten", "poweroff", "findring", "ring finden", "disconnect", "trennen",
                          "teilen", "share", "export", "kamera", "nutrition.scan", "scan", "ring suchen", "suchen",
                          "apple health verbinden", "setup.health", "erlaub", "berechtigung", "wecker stellen",
                          "openprofile", "testbanner"]
    /// Buttons that only close the current screen: used to go back, not explored.
    static let closers = ["fertig", "schließen", "abbrechen", "zurück", "back", "done", "close", "cancel", "profile.done"]

    struct Node {
        let type: XCUIElement.ElementType
        let id: String
        let label: String
        let value: String
        let frame: CGRect
        let enabled: Bool
        let inTabBar: Bool
        let inNavBar: Bool

        var key: String { id.isEmpty ? "label:\(type.rawValue):\(label)" : "id:\(id)" }
        var name: String { label.isEmpty ? id : label }
    }

    struct Step: CustomStringConvertible {
        let pages: Int
        let key: String
        let name: String
        var description: String { pages > 0 ? "\(name) (nach \(pages)× scrollen)" : name }
    }

    private var started = Date()
    private var report: [String] = []
    private var crashes: [String] = []
    private var brokenTexts: [String] = []
    private var deadButtons: [String] = []
    private var offscreen: [String] = []
    private var skippedButtons = Set<String>()
    private var notReached: [String] = []
    private var screens = 0
    private var taps = 0
    private var shot = 0

    override func setUp() async throws {
        continueAfterFailure = true   // one broken screen must not hide the others
    }

    func testWalkThroughAllScreens() throws {
        started = Date()
        for (index, start) in Self.starts.enumerated() {
            // Equal share of what is left, so the last areas are never starved by a large first one.
            let remaining = Self.budget - Date().timeIntervalSince(started)
            let deadline = Date().addingTimeInterval(remaining / Double(Self.starts.count - index))
            var seen = Set<String>()
            var audits = 0
            report.append("\n## Bereich \(start)")
            explore(start: start, path: [], depth: 0, deadline: deadline, seen: &seen, audits: &audits)
        }
        writeReport()
        if !crashes.isEmpty { XCTFail("App abgestürzt:\n" + crashes.joined(separator: "\n")) }
        if !brokenTexts.isEmpty { XCTFail("Kaputte Texte:\n" + brokenTexts.joined(separator: "\n")) }
    }

    // MARK: - Walk

    private func explore(start: String, path: [Step], depth: Int, deadline: Date, seen: inout Set<String>, audits: inout Int) {
        let app = launch(start)
        guard replay(path, in: app) else {
            report.append("- nicht wiederholbar: \(pathText(path))")
            return
        }
        let screenKey = self.screenKey(app)
        guard !seen.contains(screenKey) else { return }
        seen.insert(screenKey)
        screens += 1
        let title = screenTitle(app)
        report.append("\(String(repeating: "  ", count: depth))- **\(title)** (\(pathText(path)))")
        check(app, title: title, path: path)
        capture(start: start, title: title)
        if depth > 0, audits < Self.maxAuditsPerStart, Date() < deadline {
            audits += 1
            do {
                try AuditPolicy.run(app, name: "explore.\(start).\(title)")
            } catch {
                XCTFail("Bedienungshilfen-Prüfung \(title) (\(pathText(path))): \(error)")
            }
        }
        guard depth < Self.maxDepth else { return }

        let candidates = collectCandidates(app)
        var appAtState = true
        for candidate in candidates {
            guard Date() < deadline else {
                notReached.append("\(start): \(pathText(path + [candidate]))")
                continue
            }
            if !appAtState {
                let fresh = launch(start)
                guard replay(path, in: fresh) else { break }
            }
            appAtState = false
            let current = XCUIApplication()
            scrollToTop(current)
            for _ in 0..<candidate.pages { scrollDown(current) }
            let before = visibleSignature(current)
            guard tap(candidate, in: current) else {
                report.append("\(String(repeating: "  ", count: depth + 1))- nicht gefunden: \(candidate)")
                continue
            }
            taps += 1
            Thread.sleep(forTimeInterval: 1.2)
            dismissSystemAlert()
            switch current.state {
            case .notRunning, .unknown:
                crashes.append("- \(start): \(pathText(path + [candidate]))")
                continue
            case .runningBackground, .runningBackgroundSuspended:
                report.append("\(String(repeating: "  ", count: depth + 1))- öffnet eine andere App: \(candidate)")
                continue
            default:
                break
            }
            let afterKey = self.screenKey(current)
            if afterKey == screenKey && visibleSignature(current) == before {
                deadButtons.append("- \(start) › \(title): \(candidate)")
                appAtState = true
                continue
            }
            if afterKey == screenKey {
                // Same screen, changed content (filter, expanded card, picker): check it, no new screen.
                // The state differs from the replayed one, so the next button starts from a fresh launch.
                check(current, title: title, path: path + [candidate])
                continue
            }
            if !seen.contains(afterKey) {
                explore(start: start, path: path + [candidate], depth: depth + 1, deadline: deadline,
                        seen: &seen, audits: &audits)
            }
        }
    }

    /// Fresh app in the scenario's start state (in-memory store, fixed clock, test banner).
    @discardableResult
    private func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "YES", "-uiTestScenario", scenario, "-AppleLanguages", "(de)",
                               "-AppleLocale", "de_DE", "-dynamicType", "default", "-reduceMotion", "YES"]
        app.launch()
        _ = app.descendants(matching: .any)["screen.\(scenario)"].waitForExistence(timeout: 15)
        Thread.sleep(forTimeInterval: 0.8)
        return app
    }

    private func replay(_ path: [Step], in app: XCUIApplication) -> Bool {
        for step in path {
            scrollToTop(app)
            for _ in 0..<step.pages { scrollDown(app) }
            guard tap(step, in: app) else { return false }
            Thread.sleep(forTimeInterval: 1.2)
            dismissSystemAlert()
            guard app.state == .runningForeground else { return false }
        }
        return true
    }

    // MARK: - Candidates

    /// Every tappable button on the screen, page by page, each once.
    private func collectCandidates(_ app: XCUIApplication) -> [Step] {
        var steps: [Step] = []
        var keys = Set<String>()
        scrollToTop(app)
        var lastSignature = ""
        for page in 0..<Self.maxPages {
            if page > 0 { scrollDown(app) }
            let signature = visibleSignature(app)
            if page > 0 && signature == lastSignature { break }   // end of the scroll view
            lastSignature = signature
            for node in visibleNodes(app) where [.button, .cell].contains(node.type) && node.enabled {
                guard !node.inTabBar, !keys.contains(node.key) else { continue }
                if node.inNavBar && (node.id == "BackButton" || node.frame.minX < 40) { continue }
                let lowered = (node.id + " " + node.label).lowercased()
                if Self.closers.contains(where: { node.label.lowercased() == $0 || node.id.lowercased() == $0 }) { continue }
                if Self.skipped.contains(where: { lowered.contains($0) }) {
                    skippedButtons.insert(node.name)
                    continue
                }
                keys.insert(node.key)
                steps.append(Step(pages: page, key: node.key, name: node.name))
            }
        }
        scrollToTop(app)
        return steps
    }

    private func tap(_ step: Step, in app: XCUIApplication) -> Bool {
        guard let node = visibleNodes(app).first(where: { $0.key == step.key && $0.enabled }) else { return false }
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: node.frame.midX, dy: node.frame.midY)).tap()
        return true
    }

    // MARK: - Element tree

    private func visibleNodes(_ app: XCUIApplication) -> [Node] {
        guard let root = try? app.snapshot() else { return [] }
        let window = root.frame
        let tabTop = tabBarTop(root) ?? window.maxY
        var nodes: [Node] = []
        flatten(root, inTabBar: false, inNavBar: false, into: &nodes)
        return nodes.filter { node in
            guard node.frame.width > 1, node.frame.height > 1 else { return false }
            let mid = CGPoint(x: node.frame.midX, y: node.frame.midY)
            guard window.contains(mid) else { return false }
            return node.inTabBar || mid.y < tabTop - 4
        }
    }

    private func flatten(_ snapshot: any XCUIElementSnapshot, inTabBar: Bool, inNavBar: Bool, into nodes: inout [Node]) {
        let tab = inTabBar || snapshot.elementType == .tabBar
        let nav = inNavBar || snapshot.elementType == .navigationBar
        let value = snapshot.value.map { "\($0)" } ?? ""
        nodes.append(Node(type: snapshot.elementType, id: snapshot.identifier, label: snapshot.label, value: value,
                          frame: snapshot.frame, enabled: snapshot.isEnabled, inTabBar: tab, inNavBar: nav))
        for child in snapshot.children {
            flatten(child, inTabBar: tab, inNavBar: nav, into: &nodes)
        }
    }

    private func tabBarTop(_ snapshot: any XCUIElementSnapshot) -> CGFloat? {
        if snapshot.elementType == .tabBar { return snapshot.frame.minY }
        for child in snapshot.children {
            if let top = tabBarTop(child) { return top }
        }
        return nil
    }

    /// Identifies a screen independent of scroll position and live numbers: navigation title, screen markers,
    /// selected tab and the presence of a sheet.
    private func screenKey(_ app: XCUIApplication) -> String {
        guard let root = try? app.snapshot() else { return "?" }
        var nodes: [Node] = []
        flatten(root, inTabBar: false, inNavBar: false, into: &nodes)
        var parts: [String] = []
        parts += nodes.filter { $0.type == .navigationBar }.map { "nav:\($0.id)" }
        parts += nodes.filter { $0.inNavBar && $0.type == .staticText }.map { "title:\(Self.stripDigits($0.label))" }
        parts += nodes.filter { $0.id.hasPrefix("screen.") }.map(\.id)
        parts += nodes.filter { $0.inTabBar && $0.type == .button && $0.value.contains("1") }.map { "tab:\($0.label)" }
        parts.append("windows:\(nodes.filter { $0.type == .window }.count)")
        parts.append("sheets:\(nodes.filter { $0.type == .sheet }.count)")
        if parts.allSatisfy({ $0.hasPrefix("windows:") || $0.hasPrefix("sheets:") }) {
            // No title or marker: fall back to the first texts at the top of the screen.
            parts += nodes.filter { $0.type == .staticText }.prefix(3).map { Self.stripDigits($0.label) }
        }
        return parts.joined(separator: "|")
    }

    /// What is visible right now (labels without digits, so clocks and live values do not count as change).
    private func visibleSignature(_ app: XCUIApplication) -> String {
        visibleNodes(app)
            .filter { [.staticText, .button, .switch, .cell, .image].contains($0.type) }
            .map { "\($0.type.rawValue):\($0.id):\(Self.stripDigits($0.label)):\(Self.stripDigits($0.value))" }
            .joined(separator: "|")
    }

    private func screenTitle(_ app: XCUIApplication) -> String {
        let nodes = visibleNodes(app)
        if let title = nodes.first(where: { $0.inNavBar && $0.type == .staticText && !$0.label.isEmpty })?.label {
            return title
        }
        if let marker = nodes.first(where: { $0.id.hasPrefix("screen.") })?.id { return marker }
        return nodes.first(where: { $0.type == .staticText && !$0.label.isEmpty && !$0.label.hasPrefix("Testansicht") })?
            .label ?? "ohne Titel"
    }

    // MARK: - Checks

    /// Text that must never reach a user: Swift debug output, format placeholders, invalid numbers.
    static let brokenPatterns: [(String, String)] = [
        ("Optional(", "Swift-Debugtext"), ("%@", "Platzhalter"), ("%lld", "Platzhalter"), ("%d ", "Platzhalter"),
        ("\\(", "Platzhalter"), ("Error Domain=", "technische Fehlermeldung"), ("TODO", "Entwicklernotiz"),
        ("FIXME", "Entwicklernotiz"), ("Lorem", "Blindtext"), ("<null>", "leerer Wert"), ("(null)", "leerer Wert")
    ]
    static let brokenWords: Set<String> = ["nan", "NaN", "inf", "-inf", "Infinity", "undefined", "nil"]

    private func check(_ app: XCUIApplication, title: String, path: [Step]) {
        let nodes = visibleNodes(app)
        let width = (try? app.snapshot().frame.width) ?? 0
        for node in nodes where [.staticText, .button, .cell, .other].contains(node.type) {
            for text in [node.label, node.value] where !text.isEmpty {
                if let hit = Self.brokenPatterns.first(where: { text.contains($0.0) }) {
                    Self.note(&brokenTexts, "- \(title): „\(text.prefix(80))“ (\(hit.1)) – Weg: \(pathText(path))")
                }
                let words = text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "," || $0 == ":" }).map(String.init)
                if let word = words.first(where: { Self.brokenWords.contains($0) }) {
                    Self.note(&brokenTexts, "- \(title): „\(text.prefix(80))“ (ungültige Zahl „\(word)“) – Weg: \(pathText(path))")
                }
            }
            if node.type == .staticText, width > 0, node.frame.minX < -1 || node.frame.maxX > width + 1 {
                Self.note(&offscreen, "- \(title): „\(node.label.prefix(60))“")
            }
        }
    }

    private static func note(_ list: inout [String], _ line: String) {
        if !list.contains(line) { list.append(line) }
    }

    // MARK: - Helpers

    private func scrollDown(_ app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func scrollToTop(_ app: XCUIApplication) {
        for _ in 0..<Self.maxPages {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
    }

    /// System dialogs (permissions) belong to SpringBoard; the walk declines them.
    private func dismissSystemAlert() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        guard alert.exists else { return }
        for label in ["Nicht erlauben", "Don’t Allow", "Don't Allow", "Abbrechen", "Cancel", "OK"] {
            let button = alert.buttons[label]
            if button.exists { button.tap(); return }
        }
        alert.buttons.firstMatch.tap()
    }

    private func capture(start: String, title: String) {
        shot += 1
        let safe = title.folding(options: .diacriticInsensitive, locale: Locale(identifier: "de_DE"))
            .replacingOccurrences(of: "ß", with: "ss")
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
            .joined(separator: "-").prefix(40)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = String(format: "explore__%@__%03d__%@", start, shot, String(safe))
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func pathText(_ path: [Step]) -> String {
        path.isEmpty ? "Startbildschirm" : path.map(\.description).joined(separator: " › ")
    }

    static func stripDigits(_ text: String) -> String {
        String(text.unicodeScalars.filter { !CharacterSet.decimalDigits.contains($0) }.map(Character.init))
    }

    private func writeReport() {
        let minutes = Int(Date().timeIntervalSince(started) / 60)
        var lines = ["# KI-Rundgang durch PULSE ONE", "",
                     "\(screens) Bildschirme geprüft, \(taps) Knöpfe gedrückt, \(minutes) Minuten.", ""]
        func section(_ title: String, _ items: [String], empty: String) {
            lines.append("## \(title)")
            lines.append(contentsOf: items.isEmpty ? [empty] : items)
            lines.append("")
        }
        section("Abstürze", crashes, empty: "Keine.")
        section("Kaputte Texte", brokenTexts, empty: "Keine.")
        section("Text läuft aus dem Bildschirm", offscreen, empty: "Nichts gefunden.")
        section("Knöpfe ohne sichtbare Reaktion", deadButtons, empty: "Keine.")
        section("Absichtlich nicht gedrückt (Handtest)", skippedButtons.sorted().map { "- \($0)" }, empty: "Keine.")
        section("Aus Zeitgründen nicht erreicht", notReached.map { "- \($0)" }, empty: "Alles erreicht.")
        lines.append("## Besuchte Bildschirme")
        lines.append(contentsOf: report)
        let text = lines.joined(separator: "\n")
        print(text)
        let attachment = XCTAttachment(data: Data(text.utf8), uniformTypeIdentifier: "net.daringfireball.markdown")
        attachment.name = "explore-report.md"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
