import SwiftUI

/// Launch arguments used by UI and screenshot tests, e.g.
/// `-uiTesting YES -uiTestScenario live -dynamicType xxxl -reduceMotion YES`.
/// `-scenario <name>` is the short form of `-uiTestScenario <name>` (rebuild M1, team 06).
struct LaunchOptions: Sendable {
    var isUITesting = false
    var scenario: String?
    var dynamicTypeSize: DynamicTypeSize?
    var reduceMotion: Bool?
    /// Keeps animations running in a test scenario (`-liveMotion YES`): the M1 walkthrough video
    /// should show the motion; screenshots keep them frozen for stable images.
    var liveMotion = false

    static let current = LaunchOptions(arguments: ProcessInfo.processInfo.arguments)

    init(arguments: [String]) {
        func value(_ key: String) -> String? {
            guard let i = arguments.firstIndex(of: "-" + key), i + 1 < arguments.count else { return nil }
            return arguments[i + 1]
        }
        isUITesting = value("uiTesting") == "YES"
        scenario = value("uiTestScenario") ?? value("scenario")
        // `xxxl` is accessibility3 (screenshot matrix); `ax5` is the largest size, for the large-text checks (team 06).
        switch value("dynamicType") {
        case "xxxl": dynamicTypeSize = .accessibility3
        case "ax5": dynamicTypeSize = .accessibility5
        default: dynamicTypeSize = nil
        }
        reduceMotion = value("reduceMotion").map { $0 == "YES" }
        liveMotion = value("liveMotion") == "YES"
    }

    /// UI tests render fixed states without Bluetooth. Never true in normal use.
    var usesTestScenario: Bool { isUITesting && scenario != nil }
}
