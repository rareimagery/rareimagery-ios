import Foundation

/// Writes 24 kHz mono PCM16 little-endian samples as a WAV file (for local
/// capture round-trip checks during Task v1).
enum PCMWavWriter {
    static let sampleRate: UInt32 = 24_000
    static let channels: UInt16 = 1
    static let bitsPerSample: UInt16 = 16

    static func write(pcm16Mono24kHz data: Data, to url: URL) throws {
        var contents = Data()
        contents.reserveCapacity(44 + data.count)

        func appendU16(_ value: UInt16) {
            var le = value.littleEndian
            contents.append(Data(bytes: &le, count: 2))
        }
        func appendU32(_ value: UInt32) {
            var le = value.littleEndian
            contents.append(Data(bytes: &le, count: 4))
        }

        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = UInt32(data.count)

        contents.append(contentsOf: Array("RIFF".utf8))
        appendU32(36 + dataSize)
        contents.append(contentsOf: Array("WAVE".utf8))
        contents.append(contentsOf: Array("fmt ".utf8))
        appendU32(16) // PCM fmt chunk size
        appendU16(1) // audio format = PCM
        appendU16(channels)
        appendU32(sampleRate)
        appendU32(byteRate)
        appendU16(blockAlign)
        appendU16(bitsPerSample)
        contents.append(contentsOf: Array("data".utf8))
        appendU32(dataSize)
        contents.append(data)

        try contents.write(to: url, options: .atomic)
    }
}
