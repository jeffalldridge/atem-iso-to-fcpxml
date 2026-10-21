import Foundation

let maxMetadataBytes = 16 * 1024 * 1024

public struct Mp4Info: Sendable {
    public let width: Int
    public let height: Int
    public let frameRate: Rational
    public let frames: Int
    public let duration: Rational
    public let codec: String
    public let hasAudio: Bool
    public let timecodeFrames: Int?
    public let dropFrame: Bool
}

public struct WavInfo: Sendable {
    public let channels: Int
    public let sampleRate: Int
    public let bits: Int
    public let sampleFrames: Int
    public let timeReference: Int?  // BEXT TimeReference in samples since midnight
    public var duration: Rational { Rational(sampleFrames, sampleRate) }
}

private struct Reader {
    let handle: FileHandle
    let size: Int

    init(_ url: URL) throws {
        handle = try FileHandle(forReadingFrom: url)
        size = Int((try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0)
    }

    func close() { try? handle.close() }

    /// Lengths in media headers are untrusted: bound every read and keep it inside its box.
    func read(_ pos: Int, _ count: Int, end: Int? = nil) throws -> Data {
        if count < 0 || count > maxMetadataBytes || (end != nil && pos + count > end!) {
            throw ConversionError("Invalid or oversized media metadata field.")
        }
        try handle.seek(toOffset: UInt64(pos))
        let data = try handle.read(upToCount: count) ?? Data()
        if data.count != count { throw ConversionError("Unexpected end of file while reading MP4 structure.") }
        return data
    }

    func raw(_ pos: Int, _ count: Int) throws -> Data {
        try handle.seek(toOffset: UInt64(pos))
        return try handle.read(upToCount: count) ?? Data()
    }

    func boxes(_ start: Int, _ end: Int) throws -> [(kind: String, start: Int, end: Int)] {
        var out: [(String, Int, Int)] = []
        var pos = start
        while pos + 8 <= end {
            let head = try raw(pos, 8)
            if head.count < 8 { break }
            var size = Int(head.be32(0))
            let kind = head.ascii(4, 4)
            var header = 8
            if size == 1 {
                size = Int(try read(pos + 8, 8).be64(0))
                header = 16
            } else if size == 0 {
                size = end - pos
            }
            if size < header || pos + size > end { throw ConversionError("Invalid or truncated MP4 box.") }
            out.append((kind, pos + header, pos + size))
            pos += size
        }
        return out.map { (kind: $0.0, start: $0.1, end: $0.2) }
    }
}

extension Data {
    func be16(_ offset: Int) -> UInt16 { UInt16(self[startIndex + offset]) << 8 | UInt16(self[startIndex + offset + 1]) }
    func be32(_ offset: Int) -> UInt32 { (0..<4).reduce(UInt32(0)) { $0 << 8 | UInt32(self[startIndex + offset + $1]) } }
    func be64(_ offset: Int) -> UInt64 { (0..<8).reduce(UInt64(0)) { $0 << 8 | UInt64(self[startIndex + offset + $1]) } }
    func le16(_ offset: Int) -> UInt16 { UInt16(self[startIndex + offset]) | UInt16(self[startIndex + offset + 1]) << 8 }
    func le32(_ offset: Int) -> UInt32 { (0..<4).reversed().reduce(UInt32(0)) { $0 << 8 | UInt32(self[startIndex + offset + $1]) } }
    func le64(_ offset: Int) -> UInt64 { (0..<8).reversed().reduce(UInt64(0)) { $0 << 8 | UInt64(self[startIndex + offset + $1]) } }
    func ascii(_ offset: Int, _ count: Int) -> String { String(self[startIndex + offset ..< startIndex + offset + count].map { Character(Unicode.Scalar($0)) }) }
}

private struct Track {
    var width = 0, height = 0
    var timescale: Int?, duration: Int?
    var handler: String?
    var codec: String?
    var tcFlags: UInt32?
    var samples: Int?
    var sttsUniform: Int?
    var firstChunk: Int?
}

/// Read the MP4 (ISO BMFF) index without touching the media payload.
public func probeMp4(_ path: URL) throws -> Mp4Info {
    let reader = try Reader(path)
    defer { reader.close() }
    let name = path.lastPathComponent
    guard let moov = try reader.boxes(0, reader.size).first(where: { $0.kind == "moov" }) else {
        throw ConversionError("No MP4 index (moov) found in \(name); the recording may be incomplete.")
    }
    var tracks: [Track] = []
    for trak in try reader.boxes(moov.start, moov.end) where trak.kind == "trak" {
        var track = Track()
        for box in try reader.boxes(trak.start, trak.end) {
            if box.kind == "tkhd" {
                let version = try reader.read(box.start, 1, end: box.end)[0]
                let dims = try reader.read(box.start + (version == 1 ? 88 : 76), 8, end: box.end)
                track.width = Int(dims.be32(0) >> 16)
                track.height = Int(dims.be32(4) >> 16)
            } else if box.kind == "mdia" {
                for inner in try reader.boxes(box.start, box.end) {
                    if inner.kind == "mdhd" {
                        let version = try reader.read(inner.start, 1, end: inner.end)[0]
                        if version == 1 {
                            let data = try reader.read(inner.start + 20, 12, end: inner.end)
                            track.timescale = Int(data.be32(0)); track.duration = Int(data.be64(4))
                        } else {
                            let data = try reader.read(inner.start + 12, 8, end: inner.end)
                            track.timescale = Int(data.be32(0)); track.duration = Int(data.be32(4))
                        }
                    } else if inner.kind == "hdlr" {
                        track.handler = try reader.read(inner.start + 8, 4, end: inner.end).ascii(0, 4)
                    } else if inner.kind == "minf" {
                        for stbl in try reader.boxes(inner.start, inner.end) where stbl.kind == "stbl" {
                            try readSampleTable(reader, stbl.start, stbl.end, &track)
                        }
                    }
                }
            }
        }
        tracks.append(track)
    }
    guard let video = tracks.first(where: { $0.handler == "vide" }), let timescale = video.timescale, timescale != 0,
          let samples = video.samples, samples != 0, let duration = video.duration, duration != 0 else {
        throw ConversionError("\(name) has no video track.")
    }
    let frameRate = video.sttsUniform.map { Rational(timescale, $0) } ?? Rational(samples * timescale, duration)
    var timecodeFrames: Int?
    var drop = false
    if let tc = tracks.first(where: { $0.handler == "tmcd" && $0.tcFlags != nil }), let chunk = tc.firstChunk {
        timecodeFrames = Int(try reader.read(chunk, 4).be32(0))
        drop = (tc.tcFlags! & 1) != 0
    }
    return Mp4Info(width: video.width, height: video.height, frameRate: frameRate, frames: samples,
                   duration: Rational(duration, timescale), codec: video.codec ?? "?",
                   hasAudio: tracks.contains { $0.handler == "soun" }, timecodeFrames: timecodeFrames, dropFrame: drop)
}

private func readSampleTable(_ reader: Reader, _ start: Int, _ end: Int, _ track: inout Track) throws {
    for box in try reader.boxes(start, end) {
        let s = box.start, e = box.end
        if box.kind == "stsd" {
            let count = Int(try reader.read(s + 4, 4, end: e).be32(0))
            if count != 0 {
                let entry = try reader.read(s + 8, 8, end: e)
                let entrySize = Int(entry.be32(0))
                let entryType = entry.ascii(4, 4)
                if entrySize < 8 || s + 8 + entrySize > e { throw ConversionError("Invalid MP4 sample description length.") }
                track.codec = entryType
                if entryType == "tmcd" && entrySize >= 34 {
                    let body = try reader.read(s + 16, 25, end: e)
                    track.tcFlags = body.be32(12)
                }
            }
        } else if box.kind == "stts" {
            let count = Int(try reader.read(s + 4, 4, end: e).be32(0))
            if count > (e - s - 8) / 8 { throw ConversionError("Truncated MP4 sample timing table.") }
            let data = try reader.read(s + 8, count * 8, end: e)
            var total = 0
            var entries: [(Int, Int)] = []
            for i in 0..<count {
                let n = Int(data.be32(i * 8)), delta = Int(data.be32(i * 8 + 4))
                total += n
                entries.append((n, delta))
            }
            track.samples = total
            if entries.count == 1 || (entries.count == 2 && entries[1].0 == 1) { track.sttsUniform = entries[0].1 }
        } else if box.kind == "stco" || box.kind == "co64" {
            let count = Int(try reader.read(s + 4, 4, end: e).be32(0))
            if count != 0 {
                if box.kind == "stco" { track.firstChunk = Int(try reader.read(s + 8, 4, end: e).be32(0)) }
                else { track.firstChunk = Int(try reader.read(s + 8, 8, end: e).be64(0)) }
            }
        }
    }
}

/// Read RIFF/RF64 WAV headers, including the Broadcast WAV time reference.
public func probeWav(_ path: URL) throws -> WavInfo {
    let reader = try Reader(path)
    defer { reader.close() }
    let name = path.lastPathComponent
    let size = reader.size
    let head = try reader.raw(0, 12)
    guard head.count >= 12, head.ascii(0, 4) == "RIFF" || head.ascii(0, 4) == "RF64", head.ascii(8, 4) == "WAVE" else {
        throw ConversionError("\(name) is not a WAV file.")
    }
    var channels: Int?, rate: Int?, align: Int?, bits: Int?, dataSize: Int?, ds64Data: Int?, timeReference: Int?
    var pos = 12
    while pos + 8 <= size {
        let header = try reader.raw(pos, 8)
        let tag = header.ascii(0, 4)
        var chunkSize = Int(header.le32(4))
        let body = pos + 8
        if tag != "data" && body + chunkSize > size { throw ConversionError("\(name) has a truncated WAV chunk.") }
        if tag == "ds64" && chunkSize >= 16 {
            let data = try reader.raw(body, 16)
            ds64Data = Int(data.le64(8))
        } else if tag == "fmt " && chunkSize >= 16 {
            let data = try reader.raw(body, 16)
            var format = Int(data.le16(0))
            let ch = Int(data.le16(2)), sampleRate = Int(data.le32(4)), blockAlign = Int(data.le16(12)), bitDepth = Int(data.le16(14))
            if format == 0xFFFE && chunkSize >= 26 { format = Int(try reader.raw(body + 24, 2).le16(0)) }
            if format != 1 && format != 3 { throw ConversionError("\(name) is not PCM; ATEM WAVs should be uncompressed.") }
            channels = ch; rate = sampleRate; align = blockAlign != 0 ? blockAlign : ch * bitDepth / 8; bits = bitDepth
        } else if tag == "bext" && chunkSize >= 346 {
            timeReference = Int(try reader.raw(body + 338, 8).le64(0))
        } else if tag == "data" {
            var length = chunkSize
            if chunkSize == 0xFFFF_FFFF, let ds64 = ds64Data { length = ds64 }
            if length > size - body {
                throw ConversionError("\(name) has truncated WAV audio data; finish recording or restore the file first.")
            }
            dataSize = length
            chunkSize = length  // RF64 uses ds64, not the 32-bit sentinel; BWF metadata may follow the samples.
        }
        if body + chunkSize > size { throw ConversionError("\(name) has a truncated WAV chunk.") }
        pos = body + chunkSize + (chunkSize & 1)
    }
    guard let rate, let dataSize, let channels, let align, let bits else {
        throw ConversionError("\(name) is missing its fmt or data chunk.")
    }
    if channels <= 0 || rate <= 0 || bits <= 0 || align <= 0 { throw ConversionError("\(name) has invalid WAV format values.") }
    return WavInfo(channels: channels, sampleRate: rate, bits: bits, sampleFrames: dataSize / align, timeReference: timeReference)
}

/// Pixel size of a PNG or JPEG still from the ATEM media pool; nil if unknown.
public func probeImageSize(_ path: URL) -> (width: Int, height: Int)? {
    guard let reader = try? Reader(path) else { return nil }
    defer { reader.close() }
    guard let head = try? reader.raw(0, 32), head.count >= 24 else { return nil }
    if head.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) && head.ascii(12, 4) == "IHDR" {
        return (Int(head.be32(16)), Int(head.be32(20)))
    }
    if head[0] == 0xFF && head[1] == 0xD8 {
        var pos = 2
        while true {
            guard let marker = try? reader.raw(pos, 2), marker.count == 2, marker[0] == 0xFF else { return nil }
            pos += 2
            if [0xC0, 0xC1, 0xC2].contains(marker[1]) {
                guard let data = try? reader.raw(pos + 3, 4), data.count == 4 else { return nil }
                return (Int(data.be16(2)), Int(data.be16(0)))
            }
            guard let lengthData = try? reader.raw(pos, 2), lengthData.count == 2 else { return nil }
            let length = Int(lengthData.be16(0))
            if length < 2 { return nil }
            pos += length
        }
    }
    return nil
}
