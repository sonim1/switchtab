import Foundation
import WindowSwitcher

enum UpdateControllerTests {
    @MainActor
    static func run() throws {
        try testUnavailableControllerDisablesUpdateChecking()
        try testVersionDisplayUsesVersionAndBuild()
        try testVersionDisplayFallsBackWhenBuildIsMissing()
        try testUpdateRequestPosterPostsNotification()
        try testMenuModelIncludesUpdateItemOnlyWhenAvailable()
        try testMenuUpdateActionPostsUpdateRequest()
    }

    @MainActor
    static func testUnavailableControllerDisablesUpdateChecking() throws {
        let controller = UnavailableUpdateController()

        try expectFalse(controller.isUpdateCheckingAvailable)
        try expectFalse(controller.automaticallyChecksForUpdates)

        controller.automaticallyChecksForUpdates = true
        controller.checkForUpdates()

        try expectFalse(controller.automaticallyChecksForUpdates)
    }

    static func testVersionDisplayUsesVersionAndBuild() throws {
        let display = ApplicationVersionProvider.currentVersionDisplay(
            infoDictionary: [
                "CFBundleShortVersionString": "1.2.3",
                "CFBundleVersion": "45"
            ]
        )

        try expectEqual(display, "1.2.3 (45)")
    }

    static func testVersionDisplayFallsBackWhenBuildIsMissing() throws {
        let display = ApplicationVersionProvider.currentVersionDisplay(
            infoDictionary: [
                "CFBundleShortVersionString": "1.2.3"
            ]
        )

        try expectEqual(display, "1.2.3")
    }

    static func testUpdateRequestPosterPostsNotification() throws {
        let notificationCenter = NotificationCenter()
        let recorder = UpdateNotificationRecorder()
        let observer = notificationCenter.addObserver(
            forName: .checkForUpdates,
            object: nil,
            queue: nil
        ) { _ in
            recorder.record()
        }
        defer {
            notificationCenter.removeObserver(observer)
        }

        UpdateRequestPoster.postCheckForUpdatesRequest(notificationCenter: notificationCenter)

        try expectTrue(recorder.didPostNotification)
    }

    static func testMenuModelIncludesUpdateItemOnlyWhenAvailable() throws {
        try expectEqual(
            MenuBarMenuModel.items(updateCheckingAvailable: false),
            [.settings, .separator, .about, .quit]
        )
        try expectEqual(
            MenuBarMenuModel.items(updateCheckingAvailable: true),
            [.settings, .checkForUpdates, .separator, .about, .quit]
        )
    }

    static func testMenuUpdateActionPostsUpdateRequest() throws {
        let notificationCenter = NotificationCenter()
        let recorder = UpdateNotificationRecorder()
        let observer = notificationCenter.addObserver(
            forName: .checkForUpdates,
            object: nil,
            queue: nil
        ) { _ in
            recorder.record()
        }
        defer {
            notificationCenter.removeObserver(observer)
        }

        MenuBarUpdateAction.postCheckForUpdatesRequest(notificationCenter: notificationCenter)

        try expectTrue(recorder.didPostNotification)
    }
}

private final class UpdateNotificationRecorder: @unchecked Sendable {
    private(set) var didPostNotification = false

    func record() {
        didPostNotification = true
    }
}
