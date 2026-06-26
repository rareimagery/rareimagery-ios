import Speech

/// On-device speech-to-text for the recorded clip's audio → `voiceTranscript`.
/// `requiresOnDeviceRecognition = true` so **no audio leaves the phone**
/// (per CAPTURE-CONTRACT.md). Returns nil gracefully if unavailable/denied —
/// the valuation still proceeds from the frames.
enum SpeechService {
    static func transcribe(url: URL) async -> String? {
        let authorized = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        guard authorized,
              let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition
        else { return nil }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false

        return await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            var resumed = false
            func finish(_ value: String?) {
                if !resumed { resumed = true; cont.resume(returning: value) }
            }
            recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    finish(String(result.bestTranscription.formattedString.prefix(1000)))
                } else if error != nil {
                    finish(nil)
                }
            }
        }
    }
}
