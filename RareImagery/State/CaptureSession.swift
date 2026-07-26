import Foundation
import RareImageryAPI

@MainActor
@Observable
final class CaptureSession {
    struct Shot: Identifiable, Equatable {
        let id: UUID
        var jpegData: Data
        let pickedAt: Date

        init(jpegData: Data) {
            self.id = UUID()
            self.jpegData = jpegData
            self.pickedAt = .now
        }
    }

    enum Phase: Equatable {
        case idle
        case picking
        case working   // multipart upload + server-side Grok analysis happen together
        // Phase 4: `createFromImages` persists a Drupal product, so `ready`
        // now carries its UUID (`productId`) — the PATCH/publish target for
        // the review screen — alongside the draft used to prefill the UI.
        case ready(productId: String, draft: ProductDraft)
        case error(String)
    }

    static let maxShots = 5

    var shots: [Shot] = []
    var heroIndex: Int = 0
    var voiceTranscript: String = ""
    var intent: ProductIntent = .unknown
    var phase: Phase = .idle

    // Multi-photo curation: select up to 2 favorites for Grok Vision analysis
    // and as official product pictures. Only these are sent to analyze.
    // Matches web PhotoCurationGrid + spec "select 1-2 favorites, trash the rest".
    var selectedFavoriteIds: Set<UUID> = []

    var hero: Shot? {
        shots.indices.contains(heroIndex) ? shots[heroIndex] : nil
    }

    var canAddMore: Bool { shots.count < Self.maxShots }

    var canAnalyze: Bool {
        !selectedFavoriteIds.isEmpty && selectedFavoriteIds.count <= 2 && phase != .working
    }

    func addShot(jpegData: Data) {
        guard canAddMore else { return }
        let shot = Shot(jpegData: jpegData)
        shots.append(shot)
        if selectedFavoriteIds.count < 2 {
            selectedFavoriteIds.insert(shot.id)
        }
    }

    func removeShot(id: UUID) {
        shots.removeAll { $0.id == id }
        selectedFavoriteIds.remove(id)
        if heroIndex >= shots.count { heroIndex = max(0, shots.count - 1) }
    }

    func setHero(index: Int) {
        guard shots.indices.contains(index) else { return }
        heroIndex = index
    }

    func toggleFavorite(id: UUID) {
        if selectedFavoriteIds.contains(id) {
            selectedFavoriteIds.remove(id)
        } else if selectedFavoriteIds.count < 2 {
            selectedFavoriteIds.insert(id)
        }
    }

    func trashUnselected() {
        shots.removeAll { !selectedFavoriteIds.contains($0.id) }
        selectedFavoriteIds = selectedFavoriteIds.filter { id in
            shots.contains { $0.id == id }
        }
        if !shots.indices.contains(heroIndex) {
            heroIndex = max(0, shots.count - 1)
        }
    }

    func reset() {
        shots = []
        heroIndex = 0
        voiceTranscript = ""
        intent = .unknown
        phase = .idle
        selectedFavoriteIds = []
    }
}
