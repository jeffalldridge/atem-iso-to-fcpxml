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
        XCTAssertEqual(model.phase, .done, model.errorMessage ?? "")
        let saved = model.output
        model.open(fixture.root.appendingPathComponent("Missing.drp"))
        try await settle(model)
        XCTAssertEqual(model.phase, .done)
        XCTAssertEqual(model.output, saved)
        XCTAssertNotNil(model.errorMessage)

        model.startOver()
        XCTAssertEqual(model.phase, .empty)
        XCTAssertNil(model.errorMessage)
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
        XCTAssertEqual(model.phase, .ready, model.errorMessage ?? "")
        model.convert()
        try await settle(model)
        XCTAssertEqual(model.phase, .done, model.errorMessage ?? "")
        model.extraAudio.insert("Show MIC 2.wav")
        model.convert(replace: true)
        try await settle(model)
        XCTAssertEqual(model.phase, .ready)
        XCTAssertNotNil(model.errorMessage)
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
