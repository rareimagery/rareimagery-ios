import Foundation
import RareImageryAPI

@MainActor
@Observable
final class CaptureSession {
    struct Shot: Identifiable, Equatable {
        let id: UUID
        var jpegData: Data
        let pickedAt: Date
        var uploadedURL: URL?

        init(jpegData: Data) {
            self.id = UUID()
            self.jpegData = jpegData
            self.pickedAt = .now
            self.uploadedURL = nil
        }
    }

    enum Phase: Equatable {
        case idle
        case picking
        case uploading(completed: Int, total: Int)
        case analyzing
        case ready(ProductDraft)
        case error(String)
    }

    static let maxShots = 5

    var shots: [Shot] = []
    var heroIndex: Int = 0
    var voiceTranscript: String = ""
    var intent: ProductIntent = .unknown
    var phase: Phase = .idle

    var hero: Shot? {
        shots.indices.contains(heroIndex) ? shots[heroIndex] : nil
    }

    var canAddMore: Bool { shots.count < Self.maxShots }

    var canAnalyze: Bool {
        guard !shots.isEmpty else { return false }
        if case .analyzing = phase { return false }
        if case .uploading = phase { return false }
        return true
    }

    var allShotsUploaded: Bool {
        !shots.isEmpty && shots.allSatisfy { $0.uploadedURL != nil }
    }

    func addShot(jpegData: Data) {
        guard canAddMore else { return }
        shots.append(Shot(jpegData: jpegData))
    }

    func removeShot(id: UUID) {
        shots.removeAll { $0.id == id }
        if heroIndex >= shots.count { heroIndex = max(0, shots.count - 1) }
    }

    func setHero(index: Int) {
        guard shots.indices.contains(index) else { return }
        heroIndex = index
    }

    func markUploaded(id: UUID, url: URL) {
        guard let i = shots.firstIndex(where: { $0.id == id }) else { return }
        shots[i].uploadedURL = url
    }

    func reset() {
        shots = []
        heroIndex = 0
        voiceTranscript = ""
        intent = .unknown
        phase = .idle
    }
}
