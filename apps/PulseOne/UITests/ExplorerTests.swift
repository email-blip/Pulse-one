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
    // Nutrition is left out: the owner dropped that area (2026-11-22) and its forms give changing audit results
    // from run to run (header, footer, then the number fields). Its fixed screens stay in AccessibilityTests.
    static let starts = ["dashboard", "timeline", "intelligence", "coach", "companion", "profile", "devices"]
    /// Total wall-clock budget. The accessibility shard has about this much room next to the slowest shard.
    static let budget: TimeInterval = 11 * 60
    /// Root screen = depth 0. Screens at maxDepth are checked and photographed, their buttons are not tapped.
    static let maxDepth = 2
    static let maxAuditsPerStart = 2

    /// Buttons that would leave the test sandbox (permissions, share sheet, camera, Bluetooth) or destroy the
    /// state the walk depends on. Matched case-insensitively against identifier and label.
    static let skipped = ["lösch", "delete", "entfern", "zurücksetzen", "wiederherstellen", "verwerfen", "leeren",
                          "ausschalten", "poweroff", "findring", "ring finden", "disconnect", "trennen",
                          "teilen", "share", "export", "kamera", "nutrition.scan", "scan", "ring suchen", "suchen",
                          "apple health verbinden", "setup.health", "erlaub", "berechtigung", "wecker stellen",
                          "openprofile", "testbanner", "moveup", "movedown", "tilesize", "tilevisible"]
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

        var name: String { label.isEmpty ? id : label }
    }

    struct Step: CustomStringConvertible {
        /// Identifier, or label when the button has none.
        let id: String
        let label: String
        /// Which of several buttons with the same identifier/label (0 = first).
        let occurrence: Int
        var description: String {
            let name = label.isEmpty ? (id.isEmpty ? "Knopf ohne Beschriftung" : id) : label
            return occurrence > 0 ? "\(name) (\(occurrence + 1).)" : name
        }
    }

    private var started = Date()
    private var report: [String] = []
    private var crashes: [String] = []
    private var brokenTexts: [String] = []
    private var deadButtons: [String] = []
    private var unlabeled: [String] = []
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
            // Equal share of what is left, so a large first area never starves the last ones.
            let remaining = Self.budget - Date().timeIntervalSince(started)
            let deadline = Date().addingTimeInterval(remaining / Double(Self.starts.count - index))
            report.append("\n## Bereich \(start)")
            walk(start: start, deadline: deadline)
        }
        writeReport()
        if !crashes.isEmpty { XCTFail("App abgestürzt:\n" + crashes.joined(separator: "\n")) }
        if !brokenTexts.isEmpty { XCTFail("Kaputte Texte:\n" + brokenTexts.joined(separator: "\n")) }
    }

    // MARK: - Walk

    /// Breadth first: every button of the start screen is tapped (and its result photographed) before any
    /// screen one level deeper is expanded, so a short budget still covers each area's main screen.
    private func walk(start: String, deadline: Date) {
        var seen = Set<String>()
        var audits = 0
        var queue: [[Step]] = [[]]
        while !queue.isEmpty {
            let path = queue.removeFirst()
            guard Date() < deadline else {
                notReached.append("- \(start): alles unter \(pathText(path))")
                continue
            }
            var current = launch(start)
            if path.isEmpty {
                seen.insert(screenKey(current))
                record(current, start: start, title: screenTitle(current), path: [], depth: 0)
            } else if !replay(path, in: current) {
                report.append("\(indent(path.count))- nicht wiederholbar: \(pathText(path))")
                continue
            }
            var atState = true
            let stateKey = screenKey(current)
            let title = screenTitle(current)
            for candidate in collectCandidates(current) {
                guard Date() < deadline else {
                    notReached.append("- \(start): \(pathText(path + [candidate]))")
                    continue
                }
                if !atState {
                    current = launch(start)
                    guard replay(path, in: current) else { break }
                }
                atState = false
                let before = signature(current)
                guard tap(candidate, in: current) else {
                    report.append("\(indent(path.count + 1))- nicht erreichbar: \(candidate)")
                    atState = true
                    continue
                }
                taps += 1
                switch current.state {
                case .notRunning, .unknown:
                    crashes.append("- \(start): \(pathText(path + [candidate]))")
                    continue
                case .runningBackground, .runningBackgroundSuspended:
                    report.append("\(indent(path.count + 1))- öffnet eine andere App: \(candidate)")
                    continue
                default:
                    break
                }
                let afterKey = screenKey(current)
                if afterKey == stateKey {
                    if signature(current) == before {
                        deadButtons.append("- \(start) › \(title): \(candidate)")
                        atState = true
                    } else {
                        // Same screen, changed content (filter, expanded card, picker): check it.
                        check(current, title: title, path: path + [candidate])
                    }
                    continue
                }
                guard !seen.contains(afterKey) else { continue }
                seen.insert(afterKey)
                let newTitle = screenTitle(current)
                record(current, start: start, title: newTitle, path: path + [candidate], depth: path.count + 1)
                if path.count + 1 < Self.maxDepth {
                    queue.append(path + [candidate])
                }
                if audits < Self.maxAuditsPerStart, Date() < deadline {
                    audits += 1
                    do {
                        try AuditPolicy.run(current, name: "explore.\(start).\(newTitle)")
                    } catch {
                        XCTFail("Bedienungshilfen-Prüfung \(newTitle) (\(pathText(path + [candidate]))): \(error)")
                    }
                }
            }
        }
    }

    private func record(_ app: XCUIApplication, start: String, title: String, path: [Step], depth: Int) {
        screens += 1
        report.append("\(indent(depth))- **\(title)** (\(pathText(path)))")
        check(app, title: title, path: path)
        capture(start: start, title: title)
    }

    /// Fresh app in the scenario's start state (in-memory store, fixed clock, test banner).
    @discardableResult
    private func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "YES", "-uiTestScenario", scenario, "-AppleLanguages", "(de)",
                               "-AppleLocale", "de_DE", "-dynamicType", "default", "-reduceMotion", "YES"]
        app.launch()
        _ = app.descendants(matching: .any)["screen.\(scenario)"].waitForExistence(timeout: 15)
        return app
    }

    private func replay(_ path: [Step], in app: XCUIApplication) -> Bool {
        for step in path {
            guard tap(step, in: app), app.state == .runningForeground else { return false }
        }
        return true
    }

    // MARK: - Candidates

    /// Every enabled button of the frontmost screen (sheet if one is open), each once, in reading order.
    private func collectCandidates(_ app: XCUIApplication) -> [Step] {
        var steps: [Step] = []
        var occurrences: [String: Int] = [:]
        for node in frontNodes(app) where node.type == .button && !node.inTabBar {
            let ref = node.id.isEmpty ? "label:" + node.label : "id:" + node.id
            let occurrence = occurrences[ref, default: 0]
            occurrences[ref] = occurrence + 1
            guard node.enabled else { continue }
            if node.inNavBar && (node.id == "BackButton" || node.frame.minX < 40) { continue }
            let lowered = (node.id + " " + node.label).lowercased()
            if Self.closers.contains(where: { node.label.lowercased() == $0 || node.id.lowercased() == $0 }) { continue }
            if Self.skipped.contains(where: { lowered.contains($0) }) {
                skippedButtons.insert(node.name)
                continue
            }
            if node.label.isEmpty && node.id.isEmpty {
                Self.note(&unlabeled, "- \(screenTitle(app)): Knopf bei x \(Int(node.frame.midX)), y \(Int(node.frame.midY))")
            }
            steps.append(Step(id: node.id, label: node.label, occurrence: occurrence))
        }
        return steps
    }

    /// A button that cannot be reached (covered, off screen after four swipes) is reported, not tapped.
    private func tap(_ step: Step, in app: XCUIApplication) -> Bool {
        let query = step.id.isEmpty
            ? app.buttons.matching(NSPredicate(format: "label == %@", step.label))
            : app.buttons.matching(identifier: step.id)
        var element = query.element(boundBy: step.occurrence)
        guard element.exists, element.isEnabled else { return false }
        if !element.isHittable, let visible = query.allElementsBoundByIndex.first(where: \.isHittable) {
            // The tree can hold a hidden twin (menu item, screen below a sheet): take the one on screen.
            element = visible
        }
        // Buttons below the fold: scroll the screen until the button can be hit (at most four screens).
        var swipes = 0
        while !element.isHittable && swipes < 4 {
            app.swipeUp()
            swipes += 1
        }
        guard element.isHittable else { return false }
        element.tap()
        Thread.sleep(forTimeInterval: 0.7)
        dismissSystemAlert()
        return true
    }

    // MARK: - Element tree

    /// The frontmost presentation's elements: when a sheet is open, SwiftUI keeps the screen below in the
    /// tree, so where two branches both hold a navigation bar the later one (presented on top) wins.
    private func frontNodes(_ app: XCUIApplication) -> [Node] {
        guard let root = try? app.snapshot() else { return [] }
        var scope: any XCUIElementSnapshot = root
        while true {
            let withBars = scope.children.filter { Self.containsNavigationBar($0) }
            let others = scope.children.filter { !Self.containsNavigationBar($0) }
            guard let front = withBars.last, front.elementType != .navigationBar else { break }
            // Descend while the branch with the (frontmost) navigation bar is the only one with content,
            // or when several branches carry a bar (a presented sheet over the screen below).
            if withBars.count >= 2 || others.allSatisfy({ !Self.containsButton($0) || Self.isTabBarBranch($0) }) {
                scope = front
            } else {
                break
            }
        }
        var all: [Node] = []
        flatten(root, inTabBar: false, inNavBar: false, into: &all)
        // The tab bar lies outside a pushed screen's branch; take it from the whole tree.
        var nodes = all.filter(\.inTabBar)
        flatten(scope, inTabBar: false, inNavBar: false, into: &nodes)
        return nodes
    }

    private static func containsNavigationBar(_ snapshot: any XCUIElementSnapshot) -> Bool {
        snapshot.elementType == .navigationBar || snapshot.children.contains(where: containsNavigationBar)
    }

    private static func containsButton(_ snapshot: any XCUIElementSnapshot) -> Bool {
        snapshot.elementType == .button || snapshot.children.contains(where: containsButton)
    }

    private static func isTabBarBranch(_ snapshot: any XCUIElementSnapshot) -> Bool {
        snapshot.elementType == .tabBar || (snapshot.children.count == 1 && snapshot.children.contains(where: isTabBarBranch))
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

    /// Identifies a screen independent of scroll position and live numbers: navigation title, screen markers,
    /// selected tab and open menus or alerts.
    private func screenKey(_ app: XCUIApplication) -> String {
        let nodes = frontNodes(app)
        var parts: [String] = []
        parts += nodes.filter { $0.type == .navigationBar }.map { "nav:\($0.id)" }
        parts += nodes.filter { $0.inNavBar && $0.type == .staticText }.map { "title:\(Self.stripDigits($0.label))" }
        parts += nodes.filter { $0.id.hasPrefix("screen.") }.map(\.id)
        parts += nodes.filter { $0.inTabBar && $0.type == .button && $0.value.contains("1") }.map { "tab:\($0.label)" }
        parts += nodes.filter { [.menu, .alert, .sheet, .popover].contains($0.type) }.map { "overlay:\($0.type.rawValue)" }
        if !parts.contains(where: { $0.hasPrefix("title:") || $0.hasPrefix("screen.") }) {
            // No title or marker: the first texts identify the screen.
            parts += nodes.filter { $0.type == .staticText && !$0.label.hasPrefix("Testansicht") }.prefix(3)
                .map { Self.stripDigits($0.label) }
        }
        return parts.joined(separator: "|")
    }

    /// The content of the front screen (labels without digits, so clocks and live values are no change).
    private func signature(_ app: XCUIApplication) -> String {
        frontNodes(app)
            .filter { [.staticText, .button, .switch, .image, .textField].contains($0.type) }
            .map { "\($0.type.rawValue):\($0.id):\(Self.stripDigits($0.label)):\(Self.stripDigits($0.value)):\($0.enabled)" }
            .joined(separator: "|")
    }

    private func screenTitle(_ app: XCUIApplication) -> String {
        let nodes = frontNodes(app)
        if let title = nodes.first(where: { $0.inNavBar && $0.type == .staticText && !$0.label.isEmpty })?.label {
            return title
        }
        if nodes.contains(where: { $0.type == .menu }) { return "Menü" }
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
        let nodes = frontNodes(app)
        let width = (try? app.snapshot().frame.width) ?? 0
        for node in nodes where [.staticText, .button, .cell, .other, .textView].contains(node.type) {
            for text in [node.label, node.value] where !text.isEmpty {
                if let hit = Self.brokenPatterns.first(where: { text.contains($0.0) }) {
                    Self.note(&brokenTexts, "- \(title): „\(text.prefix(80))“ (\(hit.1)) – Weg: \(pathText(path))")
                }
                let words = text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "," || $0 == ":" }).map(String.init)
                if let word = words.first(where: { Self.brokenWords.contains($0) }) {
                    Self.note(&brokenTexts, "- \(title): „\(text.prefix(80))“ (ungültige Zahl „\(word)“) – Weg: \(pathText(path))")
                }
            }
            // Text is laid out vertically in scroll views; running off to the side means it is cut.
            if node.type == .staticText, width > 0, node.frame.width > 1, node.frame.minX < -1 || node.frame.maxX > width + 1 {
                Self.note(&offscreen, "- \(title): „\(node.label.prefix(60))“")
            }
        }
    }

    private static func note(_ list: inout [String], _ line: String) {
        if !list.contains(line) { list.append(line) }
    }

    // MARK: - Helpers

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

    private func indent(_ depth: Int) -> String { String(repeating: "  ", count: depth) }

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
        section("Knöpfe ohne Beschriftung (VoiceOver liest nichts vor)", unlabeled, empty: "Keine.")
        section("Absichtlich nicht gedrückt (Handtest)", skippedButtons.sorted().map { "- \($0)" }, empty: "Keine.")
        let shown = notReached.prefix(25) + (notReached.count > 25 ? ["- … und \(notReached.count - 25) weitere"] : [])
        section("Aus Zeitgründen nicht erreicht", Array(shown), empty: "Alles erreicht.")
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
