import XCTest
@testable import ATEMConverter

final class TimingTests: XCTestCase {
    func testVideoModes() throws {
        XCTAssertEqual(try VideoMode.parse("1080p60").rate, Rational(60))
        XCTAssertEqual(try VideoMode.parse("1080p5994").rate, Rational(60000, 1001))
        XCTAssertEqual(try VideoMode.parse("1080p29.97").rate, Rational(30000, 1001))
        XCTAssertEqual(try VideoMode.parse("1080i5994").rate, Rational(30000, 1001))
        XCTAssertTrue(try VideoMode.parse("1080i5994").interlaced)
        for bad in ["", "1080x60", "1080p999", "pal"] { XCTAssertThrowsError(try VideoMode.parse(bad)) }
    }

    func testTimecodeRoundTrips() throws {
        XCTAssertEqual(try Timecode.parse("11:34:32:07", fps: Rational(60)).frames, 2500327)
        XCTAssertEqual(Timecode.label(2500327, fps: Rational(60), drop: false), "11:34:32:07")
        XCTAssertEqual(try Timecode.parse("00:10:00;00", fps: Rational(30000, 1001)).frames, 17982)
        XCTAssertEqual(try Timecode.parse("00:01:00;04", fps: Rational(60000, 1001)).frames, 3600)
        for frames in [0, 1, 1799, 1800, 17982, 107892, 123456, 2589406] {
            let label = Timecode.label(frames, fps: Rational(30000, 1001), drop: true)
            XCTAssertEqual(try Timecode.parse(label, fps: Rational(30000, 1001)).frames, frames, label)
        }
        for fps in [Rational(30000, 1001), Rational(60000, 1001)] {
            let day = Timecode.framesPerDay(fps: fps, drop: true)
            XCTAssertEqual(Timecode.label(day, fps: fps, drop: true), "00:00:00;00")
        }
        XCTAssertThrowsError(try Timecode.parse("00:01:00;00", fps: Rational(30000, 1001)))
        XCTAssertThrowsError(try Timecode.parse("10:00:00;00", fps: Rational(60)))
        XCTAssertThrowsError(try Timecode.parse("24:00:00:00", fps: Rational(60)))
    }

    func testRationalFormatting() {
        XCTAssertEqual(Rational(2798).fcpxml, "2798s")
        XCTAssertEqual(Rational(1001, 60000).fcpxml, "1001/60000s")
        XCTAssertEqual((Rational(2, 4)).fcpxml, "1/2s")
        XCTAssertEqual(formatG(Rational(60000, 1001).doubleValue), "59.9401")
    }
}

final class ProbeTests: XCTestCase {
    func testMp4AndWavHeaders() throws {
        let dir = try Fixtures.RecordingDir(frames: 600)
        defer { dir.cleanup() }
        let info = try probeMp4(dir.root.appendingPathComponent("Show.mp4"))
        XCTAssertEqual(info.frames, 600)
        XCTAssertEqual(info.frameRate, Rational(60))
        XCTAssertEqual(info.timecodeFrames, 2160000)
        XCTAssertTrue(info.hasAudio)
        let wav = try probeWav(dir.root.appendingPathComponent("Audio Source Files/Show CAM 1.wav"))
        XCTAssertEqual(wav.sampleFrames, 480000)
        XCTAssertEqual(wav.timeReference, 2160000 / 60 * 48000)
        XCTAssertEqual(probeImageSize(dir.root.appendingPathComponent("Video ISO Files/Media Files/logo.png"))?.width, 1920)
    }
}

final class EditListTests: XCTestCase {
    func testCutsAndDissolves() throws {
        let dir = try Fixtures.RecordingDir(frames: 1200)
        defer { dir.cleanup() }
        try dir.write([Fixtures.header(), Fixtures.me("10:00:05:00", ["transitionActive": true]),
                       Fixtures.me("10:00:05:29", ["source": 2, "transitionActive": false]), Fixtures.me("10:00:20:00", ["onAir": false])])
        let rec = try openRecording(dir.drp)
        let edit = try buildEditList(rec, cameras: [1, 2])
        XCTAssertEqual(edit.cuts.map { [$0.start, $0.end] }, [[0, 315], [315, 1200]])
        XCTAssertEqual(edit.cuts[1].transitionIn?.start, 300)
        XCTAssertEqual(edit.cuts[1].transitionIn?.end, 330)
        XCTAssertEqual(edit.cuts[1].picture.key, "input-2")
    }

    func testMissingProgramUsesFirstCamera() throws {
        let dir = try Fixtures.RecordingDir(frames: 1200, program: false)
        defer { dir.cleanup() }
        try dir.write([Fixtures.header(), Fixtures.me("10:00:05:00", ["source": 3]), Fixtures.me("10:00:10:00", ["source": 1])])
        let rec = try openRecording(dir.drp)
        let plan = try makePlan(rec, { var o = PlanOptions(); o.cameras = [1, 2]; return o }())
        XCTAssertEqual(plan.edit.cuts.map { $0.picture.key }, ["input-1", "input-1", "input-1"])
        XCTAssertTrue(plan.edit.cuts[1].picture.reason.contains("showing Camera 1"))
        XCTAssertFalse(plan.angles.contains { $0.id == "program" })
    }

    func testDefaultsFollowTheLiveSwitch() throws {
        let dir = try Fixtures.RecordingDir(frames: 600)
        defer { dir.cleanup() }
        try dir.write([Fixtures.header(), Fixtures.me("10:00:03:00", ["source": 2]), Fixtures.me("10:00:06:00", ["source": 1]), Fixtures.me("10:00:10:00", ["onAir": false])])
        let plan = try makePlan(try openRecording(dir.drp))
        XCTAssertEqual(plan.angles.map { $0.id }, ["input-1", "input-2", "audio-show-mic-1", "audio-show-mic-2"])
        XCTAssertEqual(plan.mainAudioAngle, "input-1")
        XCTAssertEqual(plan.name, "Show")
        let xml = String(decoding: try buildFCPXML(plan), as: UTF8.self)
        XCTAssertTrue(xml.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE fcpxml>\n\n<fcpxml version=\"1.10\">"))
        XCTAssertTrue(xml.contains("atem%20test%20%26%20"))
    }
}

/// The Swift engine must write exactly what the Python reference writes.
final class ParityTests: XCTestCase {
    static let python = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"].first { FileManager.default.isExecutableFile(atPath: $0) }
    static let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("atem_iso_to_fcpxml.py")

    func reference(_ drp: URL, _ arguments: [String]) throws -> Data? {
        guard let python = ParityTests.python, FileManager.default.isReadableFile(atPath: ParityTests.script.path) else { return nil }
        let output = drp.deletingLastPathComponent().appendingPathComponent("reference.fcpxml")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = ["-I", ParityTests.script.path, drp.path, "-o", output.path, "--force"] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let log = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, String(decoding: log, as: UTF8.self))
        return try Data(contentsOf: output)
    }

    func compare(_ dir: Fixtures.RecordingDir, rows: [[String: Any]], arguments: [String] = [], options: PlanOptions = PlanOptions(), file: StaticString = #filePath, line: UInt = #line) throws {
        try dir.write(rows)
        let swift = try buildFCPXML(try makePlan(try openRecording(dir.drp), options))
        guard let python = try reference(dir.drp, arguments) else { throw XCTSkip("python3 and atem_iso_to_fcpxml.py are needed for parity tests") }
        if swift != python {
            let a = String(decoding: swift, as: UTF8.self).split(separator: "\n"), b = String(decoding: python, as: UTF8.self).split(separator: "\n")
            let firstDifference = zip(a, b).enumerated().first { $0.element.0 != $0.element.1 }
            XCTFail("Swift output differs from the Python reference at line \((firstDifference?.offset ?? min(a.count, b.count)) + 1):\n\(firstDifference?.element.0 ?? "")\n\(firstDifference?.element.1 ?? "")", file: file, line: line)
        }
    }

    func testPlainCuts() throws {
        let dir = try Fixtures.RecordingDir(frames: 1200)
        defer { dir.cleanup() }
        try compare(dir, rows: [Fixtures.header(), Fixtures.me("10:00:05:00", ["source": 2]), Fixtures.me("10:00:12:00", ["source": 1]), Fixtures.me("10:00:20:00", ["onAir": false])])
    }

    func testDissolvesStillsAndKeys() throws {
        let dir = try Fixtures.RecordingDir(frames: 1200, folder: "Live & Show")
        defer { dir.cleanup() }
        try compare(dir, rows: [Fixtures.header(firstSource: 8), Fixtures.me("10:00:02:00", ["transitionActive": true]),
                                Fixtures.me("10:00:02:30", ["source": 1, "transitionActive": false]), Fixtures.me("10:00:10:00", ["source": 2]),
                                ["masterTimecode": "10:00:15:00", "downstreamKeys": [["_index_": 0, "onAir": true]]],
                                ["masterTimecode": "10:00:17:00", "downstreamKeys": [["_index_": 0, "onAir": false]]],
                                Fixtures.me("10:00:18:00", ["fadeToBlack": "Active"]), Fixtures.me("10:00:19:00", ["fadeToBlack": "Inactive", "source": 5]),
                                Fixtures.me("10:00:20:00", ["onAir": false])])
    }

    func testOptionsAndWipes() throws {
        let dir = try Fixtures.RecordingDir(frames: 1200)
        defer { dir.cleanup() }
        var options = PlanOptions()
        options.cameras = [1, 2, 3]; options.audio = "MIC 1"; options.extraAudio = ["CAM 4"]; options.name = "Demo"; options.event = ""; options.includeProgram = true
        try compare(dir, rows: [Fixtures.header(transitionType: "Wipe"), Fixtures.me("10:00:05:00", ["transitionActive": true]),
                                Fixtures.me("10:00:06:00", ["source": 2, "transitionActive": false]), Fixtures.me("10:00:09:00", ["transitionActive": true]),
                                Fixtures.me("10:00:09:30", ["transitionActive": false])],
                    arguments: ["--cameras", "1,2,3", "--audio", "MIC 1", "--extra-audio", "CAM 4", "--name", "Demo", "--no-event", "--program-angle"], options: options)
        options.transitions = "cut"
        try compare(dir, rows: dir.rows, arguments: ["--cameras", "1,2,3", "--audio", "MIC 1", "--extra-audio", "CAM 4", "--name", "Demo", "--no-event", "--program-angle", "--transitions", "cut"], options: options)
        options.transitions = "program"
        try compare(dir, rows: dir.rows, arguments: ["--cameras", "1,2,3", "--audio", "MIC 1", "--extra-audio", "CAM 4", "--name", "Demo", "--no-event", "--program-angle", "--transitions", "program"], options: options)
    }

    func testMissingProgramAndWav() throws {
        let dir = try Fixtures.RecordingDir(frames: 1200, program: false)
        defer { dir.cleanup() }
        try FileManager.default.removeItem(at: dir.root.appendingPathComponent("Audio Source Files/Show CAM 2.wav"))
        try compare(dir, rows: [Fixtures.header(), Fixtures.me("10:00:05:00", ["source": 3]), Fixtures.me("10:00:08:00", ["source": 2]), Fixtures.me("10:00:10:00", ["source": 1])],
                    arguments: ["--cameras", "1,2"], options: { var o = PlanOptions(); o.cameras = [1, 2]; return o }())
    }

    func testDropFrameAndCustomNames() throws {
        let dir = try Fixtures.RecordingDir(tc: "23:59:55;00", frames: 1800, mode: "1080p5994", tcFps: 60, drop: true)
        defer { dir.cleanup() }
        var header = Fixtures.header(tc: "23:59:55;00", mode: "1080p5994")
        var sources = header["sources"] as! [[String: Any]]
        sources[1]["name"] = "Stage & Lectern"
        header["sources"] = sources
        try compare(dir, rows: [header, Fixtures.me("00:00:05;00", ["source": 2]), Fixtures.me("00:00:15;02", ["onAir": false])])
    }
}
