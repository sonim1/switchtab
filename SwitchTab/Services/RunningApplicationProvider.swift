import AppKit
import Foundation

public struct RunningApplicationSnapshot: Equatable, Sendable {
    public let processIdentifier: Int
    public let bundleIdentifier: String?
    public let localizedName: String?
    public let isRegular: Bool
    public let isTerminated: Bool
    public let isActive: Bool

    public init(
        processIdentifier: Int,
        bundleIdentifier: String?,
        localizedName: String?,
        isRegular: Bool,
        isTerminated: Bool,
        isActive: Bool
    ) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
        self.isRegular = isRegular
        self.isTerminated = isTerminated
        self.isActive = isActive
    }
}

public protocol RunningApplicationSnapshotProviding {
    func snapshots() -> [RunningApplicationSnapshot]
}

public struct RunningApplicationProvider {
    private let snapshotProvider: any RunningApplicationSnapshotProviding
    private let ownBundleIdentifier: String?

    public init(
        snapshotProvider: any RunningApplicationSnapshotProviding = NSWorkspaceRunningApplicationSnapshotProvider(),
        ownBundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) {
        self.snapshotProvider = snapshotProvider
        self.ownBundleIdentifier = Self.normalizedBundleIdentifier(ownBundleIdentifier)
    }

    public func runningApplications() -> [ApplicationItem] {
        let snapshots = snapshotProvider.snapshots()
        var applications: [ApplicationItem] = []
        applications.reserveCapacity(snapshots.count)

        var indexByIdentifier: [String: Int] = [:]
        for snapshot in snapshots {
            guard snapshot.isRegular, !snapshot.isTerminated else {
                continue
            }

            let bundleIdentifier = Self.normalizedBundleIdentifier(snapshot.bundleIdentifier)
            if let ownBundleIdentifier,
               bundleIdentifier == ownBundleIdentifier {
                continue
            }

            let id = bundleIdentifier ?? "pid:\(snapshot.processIdentifier)"
            let title = (snapshot.localizedName ?? "")
                .switcherReadableText(fallback: "Unknown Application")
            let listItem = SwitcherListItem(
                id: id,
                title: title,
                subtitle: nil,
                symbolName: "app",
                thumbnailKey: nil,
                appIconProcessIdentifier: snapshot.processIdentifier
            )
            let application = ApplicationItem(
                id: id,
                processIdentifier: snapshot.processIdentifier,
                bundleIdentifier: bundleIdentifier,
                isActive: snapshot.isActive,
                switcherListItem: listItem
            )

            if let existingIndex = indexByIdentifier[id] {
                if application.isActive, !applications[existingIndex].isActive {
                    applications[existingIndex] = application
                }
                continue
            }

            indexByIdentifier[id] = applications.count
            applications.append(application)
        }

        return applications
    }

    private static func normalizedBundleIdentifier(_ bundleIdentifier: String?) -> String? {
        guard let bundleIdentifier else {
            return nil
        }

        let trimmedIdentifier = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedIdentifier.isEmpty ? nil : trimmedIdentifier
    }
}

public final class NSWorkspaceRunningApplicationSnapshotProvider: RunningApplicationSnapshotProviding {
    public init() {}

    public func snapshots() -> [RunningApplicationSnapshot] {
        NSWorkspace.shared.runningApplications.map { application in
            RunningApplicationSnapshot(
                processIdentifier: Int(application.processIdentifier),
                bundleIdentifier: application.bundleIdentifier,
                localizedName: application.localizedName,
                isRegular: application.activationPolicy == .regular,
                isTerminated: application.isTerminated,
                isActive: application.isActive
            )
        }
    }
}
