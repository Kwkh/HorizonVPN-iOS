import UIKit

/// Feedback starts after 80 ms; gesture ownership waits for a 0.3-second
/// hold. Moving early lets the ancestor scroll pan win.
final class HorizonWallContactGesture: UIGestureRecognizer {
    var contactChanged: ((HorizonWallContactGesture) -> Void)?
    var quickTap: ((CGPoint) -> Void)?
    private var contact: UITouch?
    private var origin = CGPoint.zero
    private var holdTimer: Timer?
    private var feedbackTimer: Timer?
    private var showingFeedback = false
    private(set) var isEngaged = false

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { isEngaged }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { !isEngaged }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard contact == nil, touches.count == 1, let touch = touches.first else {
            finish(cancelled: true)
            return
        }
        contact = touch
        origin = touch.location(in: nil)
        let feedback = Timer(timeInterval: 0.08, repeats: false) { [weak self] _ in
            guard let self, self.state == .possible, self.contact != nil else { return }
            self.showingFeedback = true
            self.contactChanged?(self)
        }
        feedbackTimer = feedback
        RunLoop.main.add(feedback, forMode: .common)
        let timer = Timer(timeInterval: 0.3, repeats: false) { [weak self] _ in
            guard let self, self.state == .possible, self.contact != nil else { return }
            self.isEngaged = true
            self.showingFeedback = true
            self.state = .began
        }
        holdTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let contact, touches.contains(contact) else { return }
        if isEngaged {
            state = .changed
        } else {
            let point = contact.location(in: nil)
            // Use window coordinates so scrolling cannot move the hold origin.
            if hypot(point.x-origin.x, point.y-origin.y) >= 8 { finish(cancelled: true) }
        }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let contact, touches.contains(contact) else { return }
        if !showingFeedback && !isEngaged && state == .possible { quickTap?(origin) }
        finish(cancelled: false)
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        finish(cancelled: true)
    }
    override func reset() {
        holdTimer?.invalidate(); holdTimer = nil
        feedbackTimer?.invalidate(); feedbackTimer = nil
        showingFeedback = false
        contact = nil
        isEngaged = false
        contactChanged?(self)
        super.reset()
    }
    private func finish(cancelled: Bool) {
        holdTimer?.invalidate(); holdTimer = nil
        feedbackTimer?.invalidate(); feedbackTimer = nil
        showingFeedback = false
        contact = nil
        contactChanged?(self)
        state = isEngaged ? (cancelled ? .cancelled : .ended) : .failed
    }

    func point(in view: UIView) -> CGPoint? {
        guard showingFeedback, let contact, state == .possible || state == .began || state == .changed else { return nil }
        return isEngaged ? contact.location(in: view) : view.convert(origin, from: nil)
    }
}
