import XCTest
@testable import ATEMConverter

final class SafetyTests: XCTestCase {
    func testInvalidXMLTextIsRejectedBeforeWriting() throws {
        let dir = try Fixtures.RecordingDir()
        defer { dir.cleanup() }
        try dir.write()
        var options = PlanOptions()
        options.name = "Show\u{1}Name"
        let plan = try makePlan(try openRecording(dir.drp), options)
        XCTAssertThrowsError(try buildFCPXML(plan))
    }

    func testNonASCIIAndOversizedNumbersDoNotTrap() throws {
        XCTAssertThrowsError(try VideoMode.parse("١٠٨٠p60"))
        XCTAssertThrowsError(try Timecode.parse("١٠:00:00:00", fps: Rational(60)))
        let value = try JSONSerialization.jsonObject(with: Data("18446744073709551615".utf8), options: [.fragmentsAllowed])
        XCTAssertNil(JSONValues.int(value))
    }

    func testOversizedMP4BoxIsAnError() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        defer { try? FileManager.default.removeItem(at: path) }
        try (Fixtures.be32(1) + Data("moov".utf8) + Data(repeating: 255, count: 8)).write(to: path)
        XCTAssertThrowsError(try probeMp4(path))
    }

    func testRationalArithmeticSurvivesIntermediatesBeyondSixtyFourBits() {
        // Each cross-multiplication below exceeds Int64 before the result is reduced.
        XCTAssertTrue(Rational(1 << 40, 1_000_033) < Rational(1 << 40, 1_000_003))
        XCTAssertEqual(Rational(1 << 40, 3_000_000_019) * Rational(3_000_000_019, 1 << 41), Rational(1, 2))
        XCTAssertEqual(Rational(1 << 50, 7) - Rational(1 << 50, 7) + Rational(1, 3_000_000_019) * 3_000_000_019, Rational(1))
        XCTAssertEqual(Rational(1 << 40, 3_000_000_019) / Rational(1 << 40, 3_000_000_019), Rational(1))
    }

    func testMediaOutsideSupportedRangesIsRejected() throws {
        let dir = try Fixtures.RecordingDir(frames: 600)
        defer { dir.cleanup() }
        let video = dir.root.appendingPathComponent("Video ISO Files/Show CAM 1.mp4")
        let original = try Data(contentsOf: video)
        let stts = Data("stts".utf8) + Fixtures.be32(0, 1, 600, 1)
        let sttsAt = try XCTUnwrap(original.range(of: stts)).lowerBound
        let mdhdAt = try XCTUnwrap(original.range(of: Data("mdhd".utf8))).lowerBound + 4 + 4 + 8
        for (label, offset, value) in [("timescale", mdhdAt, UInt32.max), ("frame count", sttsAt + 12, UInt32.max), ("frame rate", sttsAt + 16, 3600)] {
            var data = original
            data.replaceSubrange(offset..<(offset + 4), with: Fixtures.be32(value))
            try data.write(to: video)
            XCTAssertThrowsError(try probeMp4(video), label) { error in
                XCTAssertTrue((error as? ConversionError)?.message.contains("outside the range") == true, "\(label): \(error)")
            }
        }
        let wav = dir.root.appendingPathComponent("Audio Source Files/Show CAM 1.wav")
        for (label, rate, reference) in [("rate", 7_999, nil), ("rate", 768_001, nil), ("time reference", 48_000, 1 << 62)] as [(String, Int, Int?)] {
            try Fixtures.makeWav(wav, sampleFrames: 48_000, timeReference: reference, rate: rate)
            XCTAssertThrowsError(try probeWav(wav), label) { error in
                XCTAssertTrue((error as? ConversionError)?.message.contains("outside the range") == true, "\(label): \(error)")
            }
        }
        try Fixtures.makeWav(wav, sampleFrames: 48_000, timeReference: 1 << 48, rate: 768_000)
        XCTAssertEqual(try probeWav(wav).sampleRate, 768_000)
    }

    func testMP4ScanStopsAtTheIndex() throws {
        let dir = try Fixtures.RecordingDir(frames: 600)
        defer { dir.cleanup() }
        let video = dir.root.appendingPathComponent("Video ISO Files/Show CAM 1.mp4")
        let handle = try FileHandle(forWritingTo: video)
        try handle.seekToEnd()
        try handle.write(contentsOf: Fixtures.be32(0xFFFF_FFF0) + Data("junk".utf8))
        try handle.close()
        XCTAssertEqual(try probeMp4(video).frames, 600)
    }

    func testZeroSampleDeltaUsesDurationFallback() throws {
        let dir = try Fixtures.RecordingDir(frames: 600)
        defer { dir.cleanup() }
        let path = dir.root.appendingPathComponent("Show.mp4")
        var bytes = try Data(contentsOf: path)
        let marker = Data("stts".utf8) + Fixtures.be32(0, 1, 600, 1)
        let range = try XCTUnwrap(bytes.range(of: marker))
        bytes.replaceSubrange((range.upperBound - 4)..<range.upperBound, with: Fixtures.be32(0))
        try bytes.write(to: path)
        XCTAssertEqual(try probeMp4(path).frameRate, Rational(60))
    }

    func testForcedOutputCreatesAndReplacesWithoutFollowingLinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent("edit.fcpxml")
        let media = root.appendingPathComponent("media.wav")
        let original = Data("original".utf8), replacement = Data("replacement".utf8)
        try OutputWriter.write(original, to: output, replace: true)
        XCTAssertEqual(try Data(contentsOf: output), original)
        XCTAssertThrowsError(try OutputWriter.write(replacement, to: output, replace: false))
        try FileManager.default.linkItem(at: output, to: media)
        try OutputWriter.write(replacement, to: output, replace: true)
        XCTAssertEqual(try Data(contentsOf: output), replacement)
        XCTAssertEqual(try Data(contentsOf: media), original)
        try FileManager.default.removeItem(at: output)
        try FileManager.default.createSymbolicLink(at: output, withDestinationURL: media)
        XCTAssertThrowsError(try OutputWriter.write(replacement, to: output, replace: true))
        XCTAssertEqual(try Data(contentsOf: media), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted(), ["edit.fcpxml", "media.wav"])
    }
}
