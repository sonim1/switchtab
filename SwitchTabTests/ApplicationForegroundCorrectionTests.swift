import CoreGraphics
import XCTest
@testable import SwitchTab

final class ApplicationForegroundCorrectionTests: XCTestCase {
    func testOnlyForeignOverlappingNormalWindowAboveTargetRequiresRaise() {
        let target = window(10, owner: 1)
        XCTAssertTrue(ApplicationForegroundCorrectionPolicy.isOccluded(
            windowIdentifier: 10, processIdentifier: 1, windows: [window(20, owner: 2), target]
        ))
        for windows in [
            [target, window(20, owner: 2)],
            [window(20, owner: 1), target],
            [window(30, owner: 1), window(20, owner: 2), target],
            [window(20, owner: 2, layer: 3), target],
            [window(20, owner: 2, x: 200), target],
            [window(20, owner: 2, alpha: 0), target],
            [window(20, owner: 2)],
            [window(20, owner: 2), window(10, owner: 3)]
        ] {
            XCTAssertFalse(ApplicationForegroundCorrectionPolicy.isOccluded(
                windowIdentifier: 10, processIdentifier: 1, windows: windows
            ))
        }
    }

    @MainActor
    func testRunsOneCorrectionForCapturedFocusedWindow() async throws {
        let corrector = RecordingForegroundCorrector()
        let coordinator = ApplicationForegroundCorrectionCoordinator(corrector: corrector)
        coordinator.schedule(processIdentifier: 1)
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(corrector.requests, ["1:10"])
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(corrector.requests, ["1:10"])
    }

    @MainActor
    func testCancellationAndNewSelectionInvalidateOldCorrection() async throws {
        let corrector = RecordingForegroundCorrector()
        let coordinator = ApplicationForegroundCorrectionCoordinator(corrector: corrector)
        coordinator.schedule(processIdentifier: 1)
        coordinator.cancel()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(corrector.requests.isEmpty)
        coordinator.schedule(processIdentifier: 1)
        coordinator.schedule(processIdentifier: 2)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(corrector.requests, ["2:10"])
    }

    @MainActor
    func testMissingFocusedWindowDoesNotScheduleCorrection() async throws {
        let corrector = RecordingForegroundCorrector()
        corrector.windowIdentifier = nil
        let coordinator = ApplicationForegroundCorrectionCoordinator(corrector: corrector)
        coordinator.schedule(processIdentifier: 1)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(corrector.requests.isEmpty)
    }

    @MainActor
    func testNewInputCancelsCorrection() async throws {
        let corrector = RecordingForegroundCorrector()
        let coordinator = ApplicationForegroundCorrectionCoordinator(corrector: corrector)
        coordinator.schedule(processIdentifier: 1)
        corrector.inputCounts = [1]
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(corrector.requests.isEmpty)
    }

    @MainActor
    func testActivationAwayCancelsEvenIfTargetActivatesAgain() async throws {
        let corrector = RecordingForegroundCorrector()
        let coordinator = ApplicationForegroundCorrectionCoordinator(corrector: corrector)
        coordinator.schedule(processIdentifier: 1)
        coordinator.applicationDidActivate(processIdentifier: 2)
        coordinator.applicationDidActivate(processIdentifier: 1)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(corrector.requests.isEmpty)
        coordinator.schedule(processIdentifier: 1)
        coordinator.applicationDidActivate(processIdentifier: 1)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(corrector.requests, ["1:10"])
    }

    private func window(
        _ id: UInt32, owner: Int, layer: Int = 0, x: CGFloat = 0, alpha: Double = 1
    ) -> ApplicationForegroundWindow {
        ApplicationForegroundWindow(
            identifier: id, processIdentifier: owner, layer: layer,
            bounds: CGRect(x: x, y: 0, width: 100, height: 100), alpha: alpha
        )
    }
}

@MainActor
private final class RecordingForegroundCorrector: ApplicationForegroundCorrecting {
    var windowIdentifier: UInt32? = 10
    var requests: [String] = []
    var inputCounts: [UInt32] = [0]

    func inputEventCounts() -> [UInt32] { inputCounts }

    func focusedWindowIdentifier(processIdentifier: Int) -> UInt32? { windowIdentifier }

    func raiseIfOccluded(processIdentifier: Int, windowIdentifier: UInt32) {
        requests.append("\(processIdentifier):\(windowIdentifier)")
    }
}
