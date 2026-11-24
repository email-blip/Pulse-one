import SwiftUI
import UIKit

/// Keeps sideways drags on the Verlauf chart away from the system back swipe. iOS 26 lets a pushed screen be
/// dismissed by swiping anywhere in its content; a fast swipe over the chart then closed the Verlauf instead of
/// moving the window, and every slow scrub started (and cancelled) a back swipe. This recogniser begins on a
/// horizontal drag, runs alongside SwiftUI's own gestures, and makes the navigation controller's pop
/// recognisers wait until it fails. Vertical drags fail it at once, so the page still scrolls.
struct ChartPanClaim: UIGestureRecognizerRepresentable {
    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.cancelsTouchesInView = false
        pan.delaysTouchesBegan = false
        pan.delaysTouchesEnded = false
        pan.delegate = context.coordinator
        return pan
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            let moved = pan.translation(in: pan.view)
            // Press-and-hold scrubbing arrives with almost no velocity: decide by the distance then.
            if velocity == .zero { return abs(moved.x) >= abs(moved.y) }
            return abs(velocity.x) >= abs(velocity.y)
        }

        func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            !Self.isBackSwipe(other, near: recognizer.view)
        }

        func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            Self.isBackSwipe(other, near: recognizer.view)
        }

        /// The pop recognisers of the navigation controller that shows `view`.
        private static func isBackSwipe(_ other: UIGestureRecognizer, near view: UIView?) -> Bool {
            var responder: UIResponder? = view
            while let current = responder {
                if let navigation = current as? UINavigationController {
                    if other === navigation.interactivePopGestureRecognizer { return true }
                    if #available(iOS 26.0, *), other === navigation.interactiveContentPopGestureRecognizer { return true }
                    return false
                }
                responder = current.next
            }
            return false
        }
    }
}
