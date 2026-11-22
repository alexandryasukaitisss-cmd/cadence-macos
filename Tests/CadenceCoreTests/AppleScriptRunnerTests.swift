import Foundation
import XCTest
@testable import CadenceCore

/// Exercises the internal AppleScript runner with pure in-process scripts.
/// These scripts never send Apple events to Music and never touch the user's
/// library; they only verify the runtime's success/failure contract.
final class AppleScriptRunnerTests: XCTestCase {
    func testExecuteReturnsResultForSuccessfulScript() throws {
        let descriptor = try AppleScriptRunner.execute("return 5")

        XCTAssertEqual(descriptor.int32Value, 5)
    }

    func testExecuteThrowsMappedErrorForFailingScript() {
        // "Can't get item 5 of {1, 2}" is a pure AppleScript language error
        // with a stable error number, independent of any application.
        XCTAssertThrowsError(try AppleScriptRunner.execute("return item 5 of {1, 2}")) { error in
            guard case let MusicLibraryError.appleScript(code, message) = error else {
                return XCTFail("Expected appleScript error, got \(error)")
            }
            XCTAssertEqual(code, AppleScriptErrorMapper.noSuchObjectNumber)
            XCTAssertFalse(message.isEmpty)
        }
    }
}
