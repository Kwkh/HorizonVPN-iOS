import SwiftUI
import VisionKit
import Vision

struct SubscriptionCameraView: UIViewControllerRepresentable {
    let active: Bool
    let onPayloads: ([String]) -> Void
    let onUnavailable: () -> Void

    func makeUIViewController(context: Context) -> CameraController {
        CameraController(onPayloads: onPayloads, onUnavailable: onUnavailable)
    }
    func updateUIViewController(_ controller: CameraController, context: Context) {
        controller.setActive(active)
    }
    static func dismantleUIViewController(_ controller: CameraController, coordinator: ()) {
        controller.setActive(false)
        controller.scanner.delegate = nil
    }

    final class CameraController: UIViewController, DataScannerViewControllerDelegate {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced, recognizesMultipleItems: true, isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true, isGuidanceEnabled: true, isHighlightingEnabled: true)
        private let onPayloads: ([String]) -> Void
        private let onUnavailable: () -> Void
        private var active = false
        private var appeared = false
        private var delivered = false

        init(onPayloads: @escaping ([String]) -> Void, onUnavailable: @escaping () -> Void) {
            self.onPayloads = onPayloads; self.onUnavailable = onUnavailable
            super.init(nibName: nil, bundle: nil)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
        override func viewDidLoad() {
            super.viewDidLoad()
            addChild(scanner)
            scanner.view.frame = view.bounds
            scanner.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(scanner.view)
            scanner.didMove(toParent: self)
            scanner.delegate = self
        }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated); appeared = true; updateScanning()
        }
        override func viewWillDisappear(_ animated: Bool) {
            appeared = false; scanner.stopScanning(); super.viewWillDisappear(animated)
        }
        func setActive(_ active: Bool) { self.active = active; updateScanning() }
        private func updateScanning() {
            guard active && appeared && !delivered else { scanner.stopScanning(); return }
            guard !scanner.isScanning else { return }
            do { try scanner.startScanning() }
            catch { DispatchQueue.main.async { [weak self] in self?.onUnavailable() } }
        }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) { receive(allItems) }
        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) { receive(allItems) }
        func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            scanner.stopScanning(); onUnavailable()
        }
        private func receive(_ items: [RecognizedItem]) {
            guard active && appeared && !delivered else { return }
            let payloads = items.compactMap { item -> String? in
                guard case .barcode(let code) = item else { return nil }
                return code.payloadStringValue
            }
            guard !payloads.isEmpty else { return }
            if (try? SubscriptionQRCode.uniqueLink(in: payloads)) != nil {
                delivered = true
                scanner.stopScanning()
            }
            onPayloads(payloads)
        }
    }
}
