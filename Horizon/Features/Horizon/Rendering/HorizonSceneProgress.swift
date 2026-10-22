import Observation
import Foundation

/// Read-only visual progress for overlays. The Metal renderer is the sole writer.
/// Keep rotation/time out of this object to avoid invalidating SwiftUI every idle frame.
@Observable
final class HorizonSceneProgress {
    var journey: Double = 0
    var formation: Double
    var completedIntroduction: UUID?
    var preparedIntroduction: UUID?
    init(formation: Double = 0) { self.formation = formation }
}
