import ServiceManagement
import XCTest
@testable import Better_Hours

@MainActor
final class LaunchAtLoginTests: XCTestCase {
    func testTurningOnReflectsTheRealStatus() {
        let model = LaunchAtLogin(service: FakeLoginItem(status: .notRegistered))
        XCTAssertFalse(model.isOn)
        model.set(true)
        XCTAssertTrue(model.isOn)
        XCTAssertNil(model.message)
        model.set(false)
        XCTAssertFalse(model.isOn)
    }

    func testFailureShowsTheErrorAndLeavesTheToggleOff() {
        let model = LaunchAtLogin(service: FakeLoginItem(status: .notRegistered, failure: "Operation not permitted"))
        model.set(true)
        XCTAssertFalse(model.isOn)
        XCTAssertEqual(model.message, "Operation not permitted")
    }

    func testPendingApprovalIsNotReportedAsOn() {
        let model = LaunchAtLogin(service: FakeLoginItem(status: .requiresApproval))
        XCTAssertFalse(model.isOn)
        XCTAssertNotNil(model.message)
    }

    func testAFailedTurnOffKeepsTheToggleOn() {
        let service = FakeLoginItem(status: .enabled, failure: "Nope")
        let model = LaunchAtLogin(service: service)
        model.set(false)
        XCTAssertTrue(model.isOn)
        XCTAssertEqual(model.message, "Nope")
    }

    func testRefreshAfterAFailureShowsTheRealStatusAndClearsTheError() {
        let service = FakeLoginItem(status: .notRegistered, failure: "Operation not permitted")
        let model = LaunchAtLogin(service: service)
        model.set(true)
        XCTAssertEqual(model.message, "Operation not permitted")
        XCTAssertFalse(model.isOn)

        service.failure = nil
        service.status = .enabled
        model.refresh()
        XCTAssertTrue(model.isOn)
        XCTAssertNil(model.message)
    }

    func testASuccessfulChangeClearsAnEarlierError() {
        let service = FakeLoginItem(status: .notRegistered, failure: "Nope")
        let model = LaunchAtLogin(service: service)
        model.set(true)
        service.failure = nil
        model.set(true)
        XCTAssertTrue(model.isOn)
        XCTAssertNil(model.message)
    }
}
