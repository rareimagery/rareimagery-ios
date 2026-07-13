import AVFoundation
import XCTest
@testable import RareImagery

final class VoiceAudioEngineTests: XCTestCase {

    func testMakeFloatBufferScalesInt16ToUnitFloat() throws {
        var samples = [Int16](repeating: 0, count: 4)
        samples[0] = 0
        samples[1] = Int16.max
        samples[2] = Int16.min
        samples[3] = Int16.max / 2

        let data = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
        let buffer = try XCTUnwrap(VoiceAudioEngine.makeFloatBuffer(pcm16: data, format: format))
        XCTAssertEqual(Int(buffer.frameLength), 4)

        let floats = buffer.floatChannelData![0]
        XCTAssertEqual(floats[0], 0, accuracy: 0.0001)
        XCTAssertEqual(floats[1], 1, accuracy: 0.0001)
        XCTAssertEqual(floats[2], -1, accuracy: 0.0001)
        XCTAssertEqual(floats[3], 0.5, accuracy: 0.01)
    }

    func testWavWriterRoundTripHeader() throws {
        // 100 ms of silence at 24 kHz mono PCM16.
        let pcm = Data(count: 2400 * 2)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-v1-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }

        try PCMWavWriter.write(pcm16Mono24kHz: pcm, to: url)
        let file = try Data(contentsOf: url)
        XCTAssertEqual(String(data: file.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: file.subdata(in: 8..<12), encoding: .ascii), "WAVE")
        XCTAssertEqual(file.count, 44 + pcm.count)

        // Sample rate at offset 24 (little-endian UInt32).
        let rate = file.subdata(in: 24..<28).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        XCTAssertEqual(rate, 24_000)
    }
}
