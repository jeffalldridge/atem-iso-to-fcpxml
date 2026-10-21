import Foundation
@testable import ATEMConverter

/// Synthetic recordings: structurally valid MP4/WAV/PNG headers with no real media, mirroring tests/test_converter.py.
enum Fixtures {
    static func box(_ kind: String, _ payload: Data) -> Data {
        var out = Data()
        var size = UInt32(8 + payload.count).bigEndian
        out.append(Data(bytes: &size, count: 4))
        out.append(kind.data(using: .ascii)!)
        out.append(payload)
        return out
    }

    static func be32(_ values: UInt32...) -> Data { var out = Data(); for v in values { var b = v.bigEndian; out.append(Data(bytes: &b, count: 4)) }; return out }
    static func be16(_ values: UInt16...) -> Data { var out = Data(); for v in values { var b = v.bigEndian; out.append(Data(bytes: &b, count: 2)) }; return out }
    static func le16(_ values: UInt16...) -> Data { var out = Data(); for v in values { var b = v.littleEndian; out.append(Data(bytes: &b, count: 2)) }; return out }
    static func le32(_ values: UInt32...) -> Data { var out = Data(); for v in values { var b = v.littleEndian; out.append(Data(bytes: &b, count: 4)) }; return out }
    static func le64(_ value: UInt64) -> Data { var b = value.littleEndian; return Data(bytes: &b, count: 8) }

    static func makeMp4(_ path: URL, frames: Int, timescale: Int = 60, frameDuration: Int = 1, width: Int = 1920, height: Int = 1080,
                        tcFrames: Int? = nil, tcFps: Int = 60, drop: Bool = false, audio: Bool = true) throws {
        let duration = frames * frameDuration
        let mdatPayload = be32(UInt32(tcFrames ?? 0)) + Data(count: 12)
        let ftyp = box("ftyp", "isom".data(using: .ascii)! + be32(1) + "isomiso4avc1".data(using: .ascii)!)
        func tkhd(_ id: Int, _ w: Int, _ h: Int) -> Data {
            var body = be32(0) + be32(0, 0, UInt32(id)) + Data(count: 4) + be32(UInt32(duration))
            body += Data(count: 8) + be16(0, 0, 0x0100, 0) + Data(count: 36) + be32(UInt32(w << 16), UInt32(h << 16))
            return box("tkhd", body)
        }
        func mdhd(_ ts: Int, _ dur: Int) -> Data { box("mdhd", be32(0) + be32(0, 0, UInt32(ts), UInt32(dur)) + be16(0x55C4, 0)) }
        func hdlr(_ kind: String) -> Data { box("hdlr", be32(0) + Data(count: 4) + kind.data(using: .ascii)! + Data(count: 12) + Data(count: 1)) }
        func stbl(_ entry: Data, _ count: Int, _ delta: Int, _ chunk: Int) -> Data {
            let stsd = box("stsd", be32(0, 1) + entry)
            let stts = box("stts", be32(0, 1) + be32(UInt32(count), UInt32(delta)))
            let stsc = box("stsc", be32(0, 1) + be32(1, UInt32(count), 1))
            let stsz = box("stsz", be32(0, 4, UInt32(count)))
            let stco = box("stco", be32(0, 1) + be32(UInt32(chunk)))
            return box("stbl", stsd + stts + stsc + stsz + stco)
        }
        func trak(_ id: Int, _ kind: String, _ w: Int, _ h: Int, _ ts: Int, _ dur: Int, _ entry: Data, _ count: Int, _ delta: Int, _ chunk: Int) -> Data {
            let dinf = box("dinf", box("dref", be32(0, 1) + box("url ", be32(1))))
            let minf = box("minf", box("vmhd", Data(count: 12)) + dinf + stbl(entry, count, delta, chunk))
            return box("trak", tkhd(id, w, h) + box("mdia", mdhd(ts, dur) + hdlr(kind) + minf))
        }
        let avc1 = box("avc1", Data(count: 6) + be16(1) + Data(count: 16) + be16(UInt16(width), UInt16(height)) + Data(count: 50))
        let tmcd = box("tmcd", Data(count: 6) + be16(1) + be32(0) + be32(drop ? 1 : 0, UInt32(tcFps), 1) + Data([UInt8(tcFps)]) + Data(count: 1))
        let mp4a = box("mp4a", Data(count: 6) + be16(1) + Data(count: 8) + be16(2, 16, 0, 0) + be32(48000 << 16))
        func moov(_ chunk: Int) -> Data {
            let mvhd = box("mvhd", be32(0) + be32(0, 0, UInt32(timescale), UInt32(duration)) + Data(count: 80))
            var tracks = trak(1, "vide", width, height, timescale, duration, avc1, frames, frameDuration, chunk + 4)
            if tcFrames != nil { tracks += trak(2, "tmcd", width, 20, timescale, duration, tmcd, 1, duration, chunk) }
            if audio { tracks += trak(3, "soun", 0, 0, 48000, frames * 800, mp4a, frames, 800, chunk + 8) }
            return box("moov", mvhd + tracks)
        }
        let first = moov(0)
        let chunk = ftyp.count + first.count + 8
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (ftyp + moov(chunk) + box("mdat", mdatPayload)).write(to: path)
    }

    static func chunkLE(_ tag: String, _ payload: Data) -> Data {
        var out = tag.data(using: .ascii)! + le32(UInt32(payload.count)) + payload
        if payload.count % 2 == 1 { out.append(0) }
        return out
    }

    static func makeWav(_ path: URL, sampleFrames: Int, timeReference: Int? = nil, rate: Int = 48000, channels: Int = 2, bits: Int = 24) throws {
        let align = channels * bits / 8
        var chunks = chunkLE("fmt ", le16(1, UInt16(channels)) + le32(UInt32(rate), UInt32(rate * align)) + le16(UInt16(align), UInt16(bits)))
        if let timeReference {
            var bext = Data(count: 256 + 32 + 32) + "2026:01:01".data(using: .ascii)! + "10:00:00".data(using: .ascii)! + le64(UInt64(timeReference))
            bext += Data(count: 2 + 64 + 10 + 180)
            chunks += chunkLE("bext", bext)
        }
        let dataSize = sampleFrames * align
        chunks += "data".data(using: .ascii)! + le32(UInt32(dataSize))
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        let header = "RIFF".data(using: .ascii)! + le32(UInt32(4 + chunks.count + dataSize)) + "WAVE".data(using: .ascii)! + chunks
        try header.write(to: path)
        let handle = try FileHandle(forWritingTo: path)
        try handle.truncate(atOffset: UInt64(header.count + dataSize))  // sparse: headers are read, samples never are
        try handle.close()
    }

    static func makePng(_ path: URL, width: Int = 1920, height: Int = 1080) throws {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        let ihdr = be32(UInt32(width), UInt32(height)) + Data([8, 2, 0, 0, 0])
        try (Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) + be32(13) + "IHDR".data(using: .ascii)! + ihdr + Data(count: 4)).write(to: path)
    }

    static func header(tc: String = "10:00:00:00", mode: String = "1080p60", name: String = "Show", firstSource: Int = 1, transitionType: String? = "Mix") -> [String: Any] {
        var block: [String: Any] = ["_index_": 0, "onAir": true, "source": firstSource, "transitionActive": false, "transitionPosition": 1.0,
                                    "fadeToBlack": "Inactive", "upstreamKeys": [["_index_": 0, "keyType": "Luma", "onAir": false, "fillSource": 8]]]
        if let transitionType { block["transitionType"] = transitionType }
        var sources: [[String: Any]] = [["_index_": 0, "name": "Black", "type": "Color"]]
        for i in 1...4 {
            sources.append(["_index_": i, "name": "Camera \(i)", "type": "Video", "volume": "DISK", "projectPath": name,
                            "file": "Video ISO Files/\(name) CAM \(i).mp4", "startTimecode": tc])
        }
        sources.append(["_index_": 5, "name": "Color Bars", "type": "ColorBars"])
        sources.append(["_index_": 8, "name": "Media Player 1", "type": "Still", "volume": "DISK", "projectPath": name,
                        "file": "Video ISO Files/Media Files/logo.png", "startTimecode": "00:00:00:00"])
        return ["version": 1, "masterTimecode": tc, "videoMode": mode, "recordingId": "00abcdef", "sources": sources,
                "mixEffectBlocks": [block], "downstreamKeys": [["_index_": 0, "onAir": false, "faderState": "Idle", "fillSource": 8]]]
    }

    static func me(_ tc: String, _ changes: [String: Any]) -> [String: Any] {
        var block: [String: Any] = ["_index_": 0]
        for (key, value) in changes { block[key] = value }
        return ["masterTimecode": tc, "mixEffectBlocks": [block]]
    }

    /// A fake ATEM recording folder on disk.
    final class RecordingDir {
        let root: URL
        let name: String
        let drp: URL
        var rows: [[String: Any]]
        let frames: Int
        let samples: Int
        let timeReference: Int

        init(tc: String = "10:00:00:00", frames: Int = 1200, name: String = "Show", folder: String = "Show", mode: String = "1080p60",
             tcFps: Int = 60, cameras: [Int] = [1, 2, 3, 4], mics: [String] = ["MIC 1", "MIC 2"], program: Bool = true, still: Bool = true, drop: Bool = false) throws {
            let base = FileManager.default.temporaryDirectory.appendingPathComponent("atem test & \(UUID().uuidString)")
            root = base.appendingPathComponent(folder)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            self.name = name
            self.frames = frames
            let fps = try VideoMode.parse(mode).rate
            let tcFrames = try Timecode.parse(tc, fps: fps).frames
            samples = Int((Double(frames) * 48000 / fps.doubleValue).rounded(.down))
            timeReference = Int((Double(tcFrames) / fps.doubleValue * 48000).rounded(.down))
            let timescale = fps.numerator, frameDuration = fps.denominator
            if program { try Fixtures.makeMp4(root.appendingPathComponent("\(name).mp4"), frames: frames, timescale: timescale, frameDuration: frameDuration, tcFrames: tcFrames, tcFps: tcFps, drop: drop) }
            for i in cameras {
                try Fixtures.makeMp4(root.appendingPathComponent("Video ISO Files/\(name) CAM \(i).mp4"), frames: frames, timescale: timescale, frameDuration: frameDuration, tcFrames: tcFrames, tcFps: tcFps, drop: drop)
                try Fixtures.makeWav(root.appendingPathComponent("Audio Source Files/\(name) CAM \(i).wav"), sampleFrames: samples, timeReference: timeReference)
            }
            for mic in mics { try Fixtures.makeWav(root.appendingPathComponent("Audio Source Files/\(name) \(mic).wav"), sampleFrames: samples, timeReference: timeReference) }
            if still { try Fixtures.makePng(root.appendingPathComponent("Video ISO Files/Media Files/logo.png")) }
            drp = root.appendingPathComponent("\(name).drp")
            rows = [Fixtures.header(tc: tc, mode: mode, name: name)]
        }

        @discardableResult
        func write(_ rows: [[String: Any]]? = nil) throws -> URL {
            let lines = try (rows ?? self.rows).map { String(decoding: try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]), as: UTF8.self) }
            try (lines.joined(separator: "\n") + "\n").write(to: drp, atomically: true, encoding: .utf8)
            return drp
        }

        func cleanup() { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
    }
}
