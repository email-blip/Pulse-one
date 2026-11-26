import SwiftUI
import UIKit

/// Test-only measurements for the UI tests (team 06). Active only with `-uiTesting YES -qaProbe YES`; otherwise every
/// call is a no-op and nothing is added to the view or accessibility tree.
///
/// Views report what XCUITest cannot see, because a tile speaks as one element:
/// - `.qaTextProbe(id, text:)`: a text's rendered line count and whether it fits (no hyphenated titles, no "14…").
/// - `QAProbe.note(id, value)`: facts such as the axis ticks drawn or "ROOK made a new assessment".
/// One element `qa.probe` at the window root carries all reports in its value: `id=report;id=report`.
@MainActor
@Observable
final class QAProbe {
    static let shared = QAProbe()

    static let isActive: Bool = UserDefaults.standard.string(forKey: "uiTesting") == "YES"
        && UserDefaults.standard.bool(forKey: "qaProbe")

    private(set) var reports: [String: String] = [:]

    static func note(_ id: String, _ value: String) {
        guard isActive, shared.reports[id] != value else { return }
        shared.reports[id] = value
    }

    var summary: String {
        reports.keys.sorted().map { "\($0)=\(reports[$0] ?? "")" }.joined(separator: ";")
    }
}

/// The single report element; RootView places it while the probe is active.
struct QAProbeReport: View {
    var body: some View {
        if QAProbe.isActive {
            Text(" ")
                .font(.caption2)
                .foregroundStyle(.clear)
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
                .accessibilityLabel("Testmessung")
                .accessibilityValue(QAProbe.shared.summary)
                .accessibilityIdentifier("qa.probe")
        }
    }
}

extension View {
    /// Reports this text as `lines:N,words:W,fits:1|0`. `lines` is the rendered line count, `fits` is 0 when the text
    /// needs more width than its lines offer even at `minimumScale` (the same factor as the text's
    /// `.minimumScaleFactor`), i.e. it is cut off ("14…"). Apply directly to the `Text`.
    func qaTextProbe(_ id: String, text: String, minimumScale: CGFloat = 1) -> some View {
        modifier(QATextProbe(id: id, words: text.split(whereSeparator: \.isWhitespace).count, minimumScale: minimumScale))
    }
}

private struct QATextProbe: ViewModifier {
    let id: String
    let words: Int
    let minimumScale: CGFloat

    func body(content: Content) -> some View {
        if QAProbe.isActive {
            content.background {
                GeometryReader { shown in
                    // The same text at its ideal size: one line, full width.
                    content.fixedSize().hidden()
                        .background {
                            GeometryReader { ideal in
                                Color.clear
                                    .onAppear { report(shown: shown.size, ideal: ideal.size, frame: shown.frame(in: .global)) }
                                    .onChange(of: shown.size) { _, size in
                                        report(shown: size, ideal: ideal.size, frame: shown.frame(in: .global))
                                    }
                                    .onChange(of: ideal.size) { _, size in
                                        report(shown: shown.size, ideal: size, frame: shown.frame(in: .global))
                                    }
                                    // A text first laid out off screen (a transition) reports again once it is in place.
                                    .onChange(of: shown.frame(in: .global).minX) { _, _ in
                                        report(shown: shown.size, ideal: ideal.size, frame: shown.frame(in: .global))
                                    }
                            }
                        }
                }
            }
        } else {
            content
        }
    }

    private func report(shown: CGSize, ideal: CGSize, frame: CGRect) {
        guard ideal.height > 0, shown.width > 0 else { return }
        let lines = max(1, Int((shown.height / ideal.height).rounded()))
        let fits = ideal.width * max(minimumScale, 0.01) <= CGFloat(lines) * shown.width + 1
        // Diagnosis only (the tests read lines, words, fits): shown/ideal size and the text's frame on screen, in points.
        let size = "w:\(Int(shown.width.rounded()))/\(Int(ideal.width.rounded()))"
            + ",h:\(Int(shown.height.rounded()))/\(Int(ideal.height.rounded()))"
        let place = "frame:\(Int(frame.minX))/\(Int(frame.minY))/\(Int(frame.width))x\(Int(frame.height))"
        let report = "lines:\(lines),words:\(words),fits:\(fits ? 1 : 0),\(size),\(place)"
        // Only a text that lies horizontally on the screen counts. SwiftUI also lays out an invisible, narrower copy
        // of the dashboard off screen (x < 0, run on 58cf1b0); its reports must not overwrite the visible tile's.
        // They stay visible for diagnosis under "offscreen.<id>". Vertical position does not matter (scrolling).
        if frame.minX >= -1, frame.maxX <= Self.screenWidth + 1 {
            QAProbe.note(id, report)
        } else {
            QAProbe.note("offscreen.\(id)", report)
        }
    }

    private static var screenWidth: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first?.screen.bounds.width ?? .greatestFiniteMagnitude
    }
}
