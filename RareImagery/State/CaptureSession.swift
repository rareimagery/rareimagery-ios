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
        if case .working = phase { return false }
        return true
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

    func reset() {
        shots = []
        heroIndex = 0
        voiceTranscript = ""
        intent = .unknown
        phase = .idle
    }
}
