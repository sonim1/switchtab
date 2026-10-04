import Foundation
import Combine

enum SwitchingPracticeFailure: Equatable {
    case accessibilityRequired, shortcutUnavailable, applicationUnavailable, noWindows, focusNotConfirmed
}

enum SwitchingPracticeState: Equatable {
    case ready, waitingForSwitch, verifying, completed, cancelled
    case failed(SwitchingPracticeFailure)
}

@MainActor
public final class SwitchingPracticeModel: ObservableObject {
    @Published private(set) var windowShortcut: ShortcutSetting?
    @Published private(set) var applicationShortcut: ShortcutSetting?
    @Published private(set) var permissionState = PermissionState(accessibility: .missing, screenRecording: .missing)
    @Published private(set) var state = SwitchingPracticeState.ready
    @Published private(set) var hasCompletedPractice = false
    @Published private(set) var hasDismissedGuide = false

    private let userDefaults: UserDefaults
    private var verificationGeneration = 0
    private var expectedWindowID: String?

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        hasCompletedPractice = userDefaults.bool(forKey: "SwitchTab.practice.completed")
        hasDismissedGuide = hasCompletedPractice || userDefaults.bool(forKey: "SwitchTab.practice.guideDismissed")
        state = hasCompletedPractice ? .completed : .ready
    }

    var canBegin: Bool { windowShortcut != nil && !permissionState.blocksFocusChanges }
    var isActive: Bool { state == .waitingForSwitch || state == .verifying }

    func update(windowShortcut: ShortcutSetting?, applicationShortcut: ShortcutSetting?, permissionState: PermissionState) {
        let registrationChanged = self.windowShortcut != windowShortcut
        self.windowShortcut = windowShortcut
        self.applicationShortcut = applicationShortcut
        self.permissionState = permissionState
        if isActive {
            if permissionState.blocksFocusChanges {
                fail(.accessibilityRequired)
            } else if registrationChanged {
                fail(.shortcutUnavailable)
            }
        }
    }

    func begin() -> Bool {
        guard !permissionState.blocksFocusChanges else {
            fail(.accessibilityRequired)
            return false
        }
        guard windowShortcut != nil else {
            fail(.shortcutUnavailable)
            return false
        }
        verificationGeneration += 1
        expectedWindowID = nil
        state = .waitingForSwitch
        return true
    }

    func confirm(windowID: String, result: WindowFocusResult) -> Int? {
        guard state == .waitingForSwitch else { return nil }
        guard result == .focused else {
            fail(result == .permissionBlocked ? .accessibilityRequired : .focusNotConfirmed)
            return nil
        }
        expectedWindowID = windowID
        state = .verifying
        return verificationGeneration
    }

    func verify(generation: Int, focusedWindowID: String?) {
        guard state == .verifying, generation == verificationGeneration else { return }
        guard focusedWindowID == expectedWindowID else {
            fail(.focusNotConfirmed)
            return
        }
        expectedWindowID = nil
        hasCompletedPractice = true
        hasDismissedGuide = true
        userDefaults.set(true, forKey: "SwitchTab.practice.completed")
        state = .completed
    }

    func cancel() {
        guard isActive else { return }
        verificationGeneration += 1
        expectedWindowID = nil
        state = .cancelled
    }

    func fail(_ reason: SwitchingPracticeFailure) {
        verificationGeneration += 1
        expectedWindowID = nil
        state = .failed(reason)
    }

    func skipGuide() {
        cancel()
        hasDismissedGuide = true
        userDefaults.set(true, forKey: "SwitchTab.practice.guideDismissed")
    }
}
