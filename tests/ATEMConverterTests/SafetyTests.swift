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
