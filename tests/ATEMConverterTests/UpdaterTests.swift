import XCTest
@testable import ATEMISOtoFCPXML

final class UpdaterTests: XCTestCase {
    @MainActor
    func testUpdateCheckWaitsForRecordingOperation() throws {
        XCTAssertThrowsError(try AppUpdater.requireIdle(isBusy: true)) { error in
            XCTAssertTrue(error.localizedDescription.contains("recording operation"))
        }
        XCTAssertNoThrow(try AppUpdater.requireIdle(isBusy: false))
    }
}
