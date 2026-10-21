import XCTest

final class CLITests: XCTestCase {
    private func run(_ arguments: [String]) throws -> (Int32, String) {
        let executable = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("atem-convert")
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationReason, .exit, "Invalid arguments must not crash")
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    func testInvalidArgumentsReturnUsefulErrors() throws {
        for arguments in [["--cameras", "one,two"], ["--cameras", ""], ["--session", "banana"], ["--session", "0"], ["first.drp", "second.drp"]] {
            let (code, message) = try run(arguments)
            XCTAssertEqual(code, 2)
            XCTAssertTrue(message.hasPrefix("Error:"), message)
        }
    }

    func testNoExtraAudioWinsRegardlessOfOptionOrder() throws {
        let fixture = try Fixtures.RecordingDir()
        defer { fixture.cleanup() }
        try fixture.write()
        for arguments in [["--no-extra-audio", "--extra-audio", "MIC 2"], ["--extra-audio", "MIC 2", "--no-extra-audio"]] {
            let output = fixture.root.appendingPathComponent("cli.fcpxml")
            let (code, message) = try run([fixture.drp.path, "-o", output.path, "--force"] + arguments)
            XCTAssertEqual(code, 0, message)
            let xml = try String(contentsOf: output, encoding: .utf8)
            XCTAssertFalse(xml.contains("audio-show-mic-2"))
        }
    }
}
