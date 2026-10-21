import XCTest
@testable import ATEMISOtoFCPXML

@MainActor
final class WorkflowTests: XCTestCase {
    private func settle(_ model: ConversionModel) async throws {
        for _ in 0..<200 {
            if !model.isBusy { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("Conversion did not finish")
    }

    func testAudioSelectionsAndSavedResultLifecycle() async throws {
        let fixture = try Fixtures.RecordingDir()
        defer { fixture.cleanup() }
        let model = ConversionModel(recordsRecentDocuments: false)
        model.open(try fixture.write())
        try await settle(model)
        XCTAssertEqual(model.phase, .ready)
        XCTAssertTrue(model.extraAudio.isEmpty)

        let mic = "Show MIC 1.wav"
        model.extraAudio.insert(mic)
        model.soundtrack = mic
        XCTAssertFalse(model.extraAudio.contains(mic))
        model.soundtrack = "Show CAM 1.wav"
        XCTAssertFalse(model.extraAudio.contains(mic))

        model.selectedCameras.remove(2)
        model.extraAudio.insert("Show CAM 2.wav")
        model.selectedCameras.insert(2)
        XCTAssertFalse(model.extraAudio.contains("Show CAM 2.wav"))
        model.selectedCameras.remove(2)
        XCTAssertFalse(model.extraAudio.contains("Show CAM 2.wav"))

        model.convert()
        try await settle(model)
        XCTAssertEqual(model.phase, .done, model.problem?.message ?? "")
        let saved = model.output
        model.open(fixture.root.appendingPathComponent("Missing.drp"))
        try await settle(model)
        XCTAssertEqual(model.phase, .done)
        XCTAssertEqual(model.output, saved)
        XCTAssertNotNil(model.problem)

        model.startOver()
        XCTAssertEqual(model.phase, .empty)
        XCTAssertNil(model.problem)
        XCTAssertTrue(model.timeline.isEmpty)
        XCTAssertNil(model.output)
    }

    func testUnusedDamagedMicrophoneDoesNotBlockOpening() async throws {
        let fixture = try Fixtures.RecordingDir()
        defer { fixture.cleanup() }
        let mic = fixture.root.appendingPathComponent("Audio Source Files/Show MIC 2.wav")
        try Data("broken WAV".utf8).write(to: mic)
        let model = ConversionModel(recordsRecentDocuments: false)
        model.open(try fixture.write())
        try await settle(model)
        XCTAssertEqual(model.phase, .ready, model.problem?.message ?? "")
        model.convert()
        try await settle(model)
        XCTAssertEqual(model.phase, .done, model.problem?.message ?? "")
        model.extraAudio.insert("Show MIC 2.wav")
        model.convert(replace: true)
        try await settle(model)
        XCTAssertEqual(model.phase, .ready)
        XCTAssertNotNil(model.problem)
    }

    func testUnchangedChoicesKeepTheSavedResult() async throws {
        let fixture = try Fixtures.RecordingDir()
        defer { fixture.cleanup() }
        let model = ConversionModel(recordsRecentDocuments: false)
        var completions: [Bool] = []
        model.operationFinished = { completions.append($0) }
        model.open(try fixture.write())
        try await settle(model)
        model.convert()
        try await settle(model)
        let saved = model.output
        let cameras = model.selectedCameras, audio = model.soundtrack, extras = model.extraAudio
        let transitions = model.transitions, program = model.includeProgramAngle
        model.selectedCameras = cameras
        model.soundtrack = audio
        model.extraAudio = extras
        model.transitions = transitions
        model.includeProgramAngle = program
        XCTAssertEqual(model.phase, .done)
        XCTAssertEqual(model.output, saved)
        XCTAssertEqual(completions, [true, true])
        model.open(fixture.root.appendingPathComponent("missing.drp"))
        try await settle(model)
        XCTAssertEqual(completions, [true, true, false])
    }

    func testQuitWaitsForCompletionAndCancelsOnFailure() {
        let termination = DeferredTermination()
        XCTAssertFalse(termination.request(isBusy: false))
        XCTAssertNil(termination.finish(succeeded: true))
        XCTAssertTrue(termination.request(isBusy: true))
        XCTAssertEqual(termination.finish(succeeded: true), true)
        XCTAssertFalse(termination.pending)
        XCTAssertNil(termination.finish(succeeded: true))
        XCTAssertTrue(termination.request(isBusy: true))
        XCTAssertEqual(termination.finish(succeeded: false), false)
        XCTAssertFalse(termination.pending)
    }

    /// The window's choices, the summary line and the written XML must describe the same audio: every WAV the
    /// choices imply appears exactly once, and nothing else does.
    func testWrittenAudioMatchesTheVisibleChoices() async throws {
        let fixture = try Fixtures.RecordingDir()
        defer { fixture.cleanup() }
        let model = ConversionModel(recordsRecentDocuments: false)
        model.open(try fixture.write())
        try await settle(model)
        let all = ["Show CAM 1.wav", "Show CAM 2.wav", "Show CAM 3.wav", "Show CAM 4.wav", "Show MIC 1.wav", "Show MIC 2.wav"]
        let cases: [(cameras: Set<Int>, soundtrack: String, extras: [String])] = [
            ([1], "Show CAM 1.wav", []),
            ([1, 2], "Show MIC 1.wav", ["Show MIC 2.wav"]),
            ([2], "Show CAM 3.wav", ["Show CAM 4.wav", "Show MIC 1.wav"]),   // soundtrack from an unselected camera
            ([1, 2, 3], "Show CAM 2.wav", all),                              // extras that are already included must be ignored
        ]
        for (index, test) in cases.enumerated() {
            model.selectedCameras = test.cameras
            model.soundtrack = test.soundtrack
            model.extraAudio = Set(test.extras)
            // What the window offers as extras never repeats a camera WAV or the soundtrack.
            let offered = Set(model.optionalAudio.map(\.id))
            XCTAssertTrue(offered.isDisjoint(with: Set(test.cameras.map { "Show CAM \($0).wav" } + [test.soundtrack])), "case \(index)")
            let expected = Set(test.cameras.map { "Show CAM \($0).wav" } + [test.soundtrack] + model.extraAudio)
            model.convert(replace: true)
            try await settle(model)
            XCTAssertEqual(model.phase, .done, model.problem?.message ?? "case \(index)")
            let xml = try String(contentsOf: fixture.root.appendingPathComponent("Show.fcpxml"), encoding: .utf8)
            let written = xml.components(separatedBy: "<asset ").dropFirst().compactMap { chunk -> String? in
                guard let start = chunk.range(of: "name=\"")?.upperBound, let end = chunk[start...].firstIndex(of: "\"") else { return nil }
                let name = String(chunk[start..<end])
                return name.hasSuffix(".wav") ? name : nil
            }
            XCTAssertEqual(written.count, Set(written).count, "a WAV was written twice in case \(index)")
            XCTAssertEqual(Set(written), expected, "case \(index)")
        }
    }

    func testMultipleSessionsExplainTheCommandLineOption() async throws {
        let fixture = try Fixtures.RecordingDir()
        defer { fixture.cleanup() }
        let model = ConversionModel(recordsRecentDocuments: false)
        model.open(try fixture.write([Fixtures.header(), Fixtures.me("10:00:10:00", ["source": 2]), Fixtures.header(tc: "11:00:00:00")]))
        try await settle(model)
        XCTAssertEqual(model.phase, .empty)
        let problem = try XCTUnwrap(model.problem)
        XCTAssertEqual(problem.title, "This Recording Has 2 Sessions")
        XCTAssertTrue(problem.message.contains("--session"))
    }

    func testDestinationIsStatedBeforeConversionAndReadingNeverDefersQuit() async throws {
        let fixture = try Fixtures.RecordingDir()
        defer { fixture.cleanup() }
        let model = ConversionModel(recordsRecentDocuments: false)
        model.open(try fixture.write())
        XCTAssertEqual(model.phase, .loading)
        XCTAssertTrue(model.isBusy)
        XCTAssertFalse(model.isPublishing, "Quitting during a read must not wait")
        try await settle(model)
        XCTAssertEqual(model.destinationNote, "Saves Show.fcpxml next to the recording.")
        model.convert()
        XCTAssertTrue(model.isPublishing)
        try await settle(model)
        model.includeProgramAngle = true
        XCTAssertTrue(model.destinationNote.contains("already exists"), model.destinationNote)
    }

    func testChangingChoicesRequiresExplicitReplacement() async throws {
        let fixture = try Fixtures.RecordingDir()
        defer { fixture.cleanup() }
        let model = ConversionModel(recordsRecentDocuments: false)
        model.open(try fixture.write())
        try await settle(model)
        model.convert()
        try await settle(model)
        XCTAssertEqual(model.phase, .done)
        model.includeProgramAngle = true
        XCTAssertEqual(model.phase, .ready)
        model.convert()
        XCTAssertTrue(model.showReplaceConfirmation)
        XCTAssertEqual(model.phase, .ready)
    }
}
