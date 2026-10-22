import SwiftUI
import UIKit

/// Hide only the tab bar's presentation during the introduction. Keeping its
/// layout reservation preserves the original home viewport throughout the handoff.
struct HorizonIntroductionTabBar: UIViewControllerRepresentable {
    let hidden: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.suppressed = hidden
        controller.duration = reduceMotion ? 0.2 : 0.45
        controller.apply()
    }
    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
        controller.restore(animated:false)
    }

    final class Controller: UIViewController {
        var suppressed = true
        var duration: TimeInterval = 0.45
        private weak var managedBar: UITabBar?
        private var original: (alpha: CGFloat, interactive: Bool, accessibilityHidden: Bool)?

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
        }
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent:parent)
            apply()
        }
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            apply()
        }
        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            apply()
        }
        func apply() {
            guard suppressed else { restore(animated:viewIfLoaded?.window != nil); return }
            guard let bar = tabBarController?.tabBar else { return }
            if managedBar !== bar {
                restore(animated:false)
                managedBar = bar
            }
            if original == nil {
                original = (bar.alpha,bar.isUserInteractionEnabled,bar.accessibilityElementsHidden)
            }
            bar.alpha = 0
            bar.isUserInteractionEnabled = false
            bar.accessibilityElementsHidden = true
        }
        func restore(animated: Bool) {
            guard let bar = managedBar, let original else { return }
            self.original = nil
            managedBar = nil
            bar.isUserInteractionEnabled = original.interactive
            bar.accessibilityElementsHidden = original.accessibilityHidden
            if animated {
                UIView.animate(withDuration:duration,delay:0,options:[.beginFromCurrentState,.allowUserInteraction]) {
                    bar.alpha = original.alpha
                }
            } else { bar.alpha = original.alpha }
        }
    }
}
