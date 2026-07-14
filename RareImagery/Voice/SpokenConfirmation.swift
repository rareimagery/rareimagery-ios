import AVFoundation

final class SpokenConfirmation {
    static let shared = SpokenConfirmation()

    private let synth = AVSpeechSynthesizer()

    /// Speaks a short confirmation after a successful product creation.
    /// Path C stopgap — client-side TTS only. Replaced by real Grok voice
    /// flow (Task v3) once /api/v1/analyze-capture ships.
    func speakProductCreated(title: String?) {
        let phrase: String
        if let title, !title.isEmpty, title != "New Item — please edit" {
            phrase = "Your new product, \(title), has been created. Tap to edit the details."
        } else {
            phrase = "Your new product has been created. Tap to edit the details."
        }

        // Respect the current audio session — never override a call/music.
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback, mode: .spokenAudio, options: [.duckOthers, .mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true, options: [])
        } catch {
            return  // fail silent; UX is nice-to-have
        }

        let utterance = AVSpeechUtterance(string: phrase)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.postUtteranceDelay = 0.2
        synth.speak(utterance)
    }

    func cancel() {
        synth.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
