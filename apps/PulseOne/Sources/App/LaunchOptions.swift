import SwiftUI

/// Launch arguments used by UI and screenshot tests, e.g.
/// `-uiTesting YES -uiTestScenario live -dynamicType xxxl -reduceMotion YES`.
struct LaunchOptions: Sendable {
    var isUITesting = false
    var scenario: String?
    var dynamicTypeSize: DynamicTypeSize?
    var reduceMotion: Bool?

    static let current = LaunchOptions(arguments: ProcessInfo.processInfo.arguments)

    init(arguments: [String]) {
        func value(_ key: String) -> String? {
            guard let i = arguments.firstIndex(of: "-" + key), i + 1 < arguments.count else { return nil }
            return arguments[i + 1]
        }
        isUITesting = value("uiTesting") == "YES"
        scenario = value("uiTestScenario")
        dynamicTypeSize = value("dynamicType") == "xxxl" ? .accessibility3 : nil
        reduceMotion = value("reduceMotion").map { $0 == "YES" }
    }

    /// UI tests render fixed states without Bluetooth. Never true in normal use.
    var usesTestScenario: Bool { isUITesting && scenario != nil }
}
