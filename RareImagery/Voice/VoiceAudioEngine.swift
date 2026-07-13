import AVFoundation
import Foundation

/// Mic capture + playback for xAI Realtime (24 kHz mono PCM16).
///
/// Captured chunks are ~100 ms (`2400` frames). Playback accepts raw PCM16
/// deltas from the server; barge-in calls `stopPlaybackImmediately()`.
@MainActor
final class VoiceAudioEngine {
    enum Failure: Error, LocalizedError {
        case engineStart(Error)
        case converterUnavailable
        case session(Error)

        var errorDescription: String? {
            switch self {
            case .engineStart(let e): return "Couldn't start audio: \(e.localizedDescription)"
            case .converterUnavailable: return "Couldn't configure audio converter."
            case .session(let e): return "Couldn't configure audio session: \(e.localizedDescription)"
            }
        }
    }

    /// Emits ~100 ms chunks of 24 kHz mono PCM16 (little-endian Int16).
    var onCapturedChunk: ((Data) -> Void)?

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var converter: AVAudioConverter?
    private var isRunning = false
    private var captureAccumulator = Data()
    private let captureChunkBytes = 2400 * MemoryLayout<Int16>.size // ~100 ms

    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 24_000,
        channels: 1,
        interleaved: true
    )!

    private let playbackFormat = AVAudioFormat(
        standardFormatWithSampleRate: 24_000,
        channels: 1
    )!

    private var interruptionObserver: NSObjectProtocol?
    private var routeObserver: NSObjectProtocol?

    // MARK: - Lifecycle

    func start() throws {
        guard !isRunning else { return }
        try configureSession()
        try installTapAndStart()
        observeSessionEvents()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        removeObservers()
        engine.inputNode.removeTap(onBus: 0)
        playerNode.stop()
        engine.stop()
        converter = nil
        captureAccumulator.removeAll(keepingCapacity: false)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    // MARK: - Playback

    /// Queues a PCM16 mono 24 kHz delta for speaker playback (FIFO via player node).
    func enqueuePlayback(pcm16 data: Data) {
        guard isRunning, !data.isEmpty else { return }
        guard let buffer = Self.makeFloatBuffer(pcm16: data, format: playbackFormat) else { return }
        if !playerNode.isPlaying {
            playerNode.play()
        }
        playerNode.scheduleBuffer(buffer, completionHandler: nil)
    }

    /// Barge-in: drop queued assistant audio immediately.
    func stopPlaybackImmediately() {
        playerNode.stop()
        if isRunning {
            playerNode.play()
        }
    }

    // MARK: - Session

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
            )
            try session.setPreferredSampleRate(24_000)
            try session.setActive(true, options: [])
        } catch {
            throw Failure.session(error)
        }
    }

    private func installTapAndStart() throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw Failure.converterUnavailable
        }
        self.converter = converter

        if !engine.attachedNodes.contains(playerNode) {
            engine.attach(playerNode)
        }
        engine.connect(playerNode, to: engine.mainMixerNode, format: playbackFormat)

        let targetFormat = self.targetFormat
        let chunkFrames = AVAudioFrameCount(2400)
        input.installTap(onBus: 0, bufferSize: chunkFrames, format: inputFormat) { [weak self] buffer, _ in
            // Convert on the audio callback thread — the tap buffer is only
            // valid here. Hop to MainActor with the resulting PCM16 bytes.
            guard let pcm16 = VoiceAudioEngine.convertToPCM16(
                buffer: buffer,
                inputFormat: inputFormat,
                targetFormat: targetFormat,
                converter: converter
            ), !pcm16.isEmpty else { return }
            Task { @MainActor [weak self] in
                self?.appendCapturedPCM16(pcm16)
            }
        }

        do {
            try engine.start()
            playerNode.play()
        } catch {
            input.removeTap(onBus: 0)
            throw Failure.engineStart(error)
        }
    }

    private func appendCapturedPCM16(_ chunk: Data) {
        guard isRunning else { return }
        captureAccumulator.append(chunk)
        while captureAccumulator.count >= captureChunkBytes {
            let piece = captureAccumulator.prefix(captureChunkBytes)
            captureAccumulator.removeFirst(captureChunkBytes)
            onCapturedChunk?(Data(piece))
        }
    }

    nonisolated private static func convertToPCM16(
        buffer: AVAudioPCMBuffer,
        inputFormat: AVAudioFormat,
        targetFormat: AVAudioFormat,
        converter: AVAudioConverter?
    ) -> Data? {
        guard let converter else { return nil }
        let ratio = targetFormat.sampleRate / inputFormat.sampleRate
        let outFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outFrames) else { return nil }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        let status = converter.convert(to: out, error: &error, withInputFrom: inputBlock)
        guard status != .error, error == nil, out.frameLength > 0,
              let channels = out.int16ChannelData else { return nil }

        let byteCount = Int(out.frameLength) * MemoryLayout<Int16>.size
        return Data(bytes: channels[0], count: byteCount)
    }

    // MARK: - Interruptions / route

    private func observeSessionEvents() {
        removeObservers()
        let center = NotificationCenter.default
        interruptionObserver = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                self?.handleInterruption(note)
            }
        }
        routeObserver = center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                self?.handleRouteChange(note)
            }
        }
    }

    private func removeObservers() {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
        }
        if let routeObserver {
            NotificationCenter.default.removeObserver(routeObserver)
            self.routeObserver = nil
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            stopPlaybackImmediately()
            engine.pause()
        case .ended:
            let options = (info[AVAudioSessionInterruptionOptionKey] as? UInt)
                .map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
            if options.contains(.shouldResume), isRunning {
                try? AVAudioSession.sharedInstance().setActive(true)
                try? engine.start()
                playerNode.play()
            }
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard isRunning else { return }
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

        switch reason {
        case .oldDeviceUnavailable:
            // e.g. Bluetooth headset unplugged — keep engine alive on speaker.
            try? AVAudioSession.sharedInstance().setActive(true)
            if !engine.isRunning {
                try? engine.start()
                playerNode.play()
            }
        default:
            break
        }
    }

    // MARK: - PCM helpers

    /// Int16 little-endian mono → Float32 non-interleaved buffer at 24 kHz.
    nonisolated static func makeFloatBuffer(pcm16 data: Data, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frameCount = data.count / MemoryLayout<Int16>.size
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        guard let channels = buffer.floatChannelData else { return nil }

        data.withUnsafeBytes { raw in
            let source = raw.bindMemory(to: Int16.self)
            let out = channels[0]
            for i in 0..<frameCount {
                out[i] = Float(source[i]) / Float(Int16.max)
            }
        }
        return buffer
    }
}
