@testable import SwitchTab
import XCTest

final class SwitcherModeSwitchMemoryTests: XCTestCase {
    func testRemembersApplicationAndWindowPerOwningProcess() {
        var memory = SwitcherModeSwitchMemory()
        XCTAssertTrue(memory.isEmpty)

        memory.rememberApplication(id: "com.apple.Safari")
        memory.rememberWindow(id: "501-7", ownerProcessIdentifier: 501)
        memory.rememberWindow(id: "502-3", ownerProcessIdentifier: 502)

        XCTAssertEqual(memory.applicationID, "com.apple.Safari")
        XCTAssertEqual(memory.windowID(ownerProcessIdentifier: 501), "501-7")
        XCTAssertEqual(memory.windowID(ownerProcessIdentifier: 502), "502-3")
        XCTAssertNil(memory.windowID(ownerProcessIdentifier: 503))
    }

    func testForgettingOneProcessKeepsTheOthers() {
        var memory = SwitcherModeSwitchMemory()
        memory.rememberWindow(id: "501-7", ownerProcessIdentifier: 501)
        memory.rememberWindow(id: "502-3", ownerProcessIdentifier: 502)

        memory.forgetWindows(ownerProcessIdentifier: 501)

        XCTAssertNil(memory.windowID(ownerProcessIdentifier: 501))
        XCTAssertEqual(memory.windowID(ownerProcessIdentifier: 502), "502-3")
    }

    func testResetClearsTheWholeSession() {
        var memory = SwitcherModeSwitchMemory()
        memory.rememberApplication(id: "com.apple.Safari")
        memory.rememberWindow(id: "501-7", ownerProcessIdentifier: 501)

        memory.reset()

        XCTAssertTrue(memory.isEmpty)
        XCTAssertNil(memory.applicationID)
        XCTAssertNil(memory.windowID(ownerProcessIdentifier: 501))
    }

    func testResumedIndexAdvancesFromTheRememberedPosition() {
        XCTAssertEqual(
            SwitcherModeSwitchMemory.resumedIndex(
                itemCount: 4,
                rememberedIndex: 1,
                advance: 1,
                fallback: 0
            ),
            2
        )
        XCTAssertEqual(
            SwitcherModeSwitchMemory.resumedIndex(
                itemCount: 4,
                rememberedIndex: 1,
                advance: -1,
                fallback: 0
            ),
            0
        )
    }

    func testResumedIndexWrapsAroundBothEnds() {
        XCTAssertEqual(
            SwitcherModeSwitchMemory.resumedIndex(
                itemCount: 3,
                rememberedIndex: 2,
                advance: 1,
                fallback: 0
            ),
            0
        )
        XCTAssertEqual(
            SwitcherModeSwitchMemory.resumedIndex(
                itemCount: 3,
                rememberedIndex: 0,
                advance: -1,
                fallback: 0
            ),
            2
        )
    }

    func testResumedIndexHoldsPositionWhenNotAdvancing() {
        XCTAssertEqual(
            SwitcherModeSwitchMemory.resumedIndex(
                itemCount: 5,
                rememberedIndex: 3,
                advance: 0,
                fallback: 0
            ),
            3
        )
    }

    func testResumedIndexFallsBackWithoutUsableMemory() {
        XCTAssertEqual(
            SwitcherModeSwitchMemory.resumedIndex(
                itemCount: 4,
                rememberedIndex: nil,
                advance: 1,
                fallback: 1
            ),
            1
        )
        // A remembered item that is no longer listed must not advance past a
        // stale position.
        XCTAssertEqual(
            SwitcherModeSwitchMemory.resumedIndex(
                itemCount: 4,
                rememberedIndex: 9,
                advance: 1,
                fallback: 1
            ),
            1
        )
        XCTAssertEqual(
            SwitcherModeSwitchMemory.resumedIndex(
                itemCount: 2,
                rememberedIndex: nil,
                advance: 1,
                fallback: 7
            ),
            1
        )
    }

    func testResumedIndexOnAnEmptyListIsZero() {
        XCTAssertEqual(
            SwitcherModeSwitchMemory.resumedIndex(
                itemCount: 0,
                rememberedIndex: 2,
                advance: 1,
                fallback: 3
            ),
            0
        )
    }
}
