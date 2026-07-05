import AppKit

@MainActor
public final class ApplicationIconStore {
    private enum CachedIcon {
        case resolved(NSImage)
        case missing
    }

    private let resolver: @MainActor (Int) -> NSImage?
    private var icons: [Int: CachedIcon] = [:]

    public init(
        resolver: @escaping @MainActor (Int) -> NSImage? = {
            NSRunningApplication(processIdentifier: pid_t($0))?.icon
        }
    ) {
        self.resolver = resolver
    }

    public func retainOnlyCachedIcons(for items: [SwitcherListItem]) {
        guard !icons.isEmpty else {
            return
        }

        guard !items.isEmpty else {
            icons.removeAll(keepingCapacity: true)
            return
        }

        var presentProcessIdentifiers = Set<Int>()
        for item in items {
            if let processIdentifier = item.appIconProcessIdentifier {
                presentProcessIdentifiers.insert(processIdentifier)
            }
        }

        icons = icons.filter { presentProcessIdentifiers.contains($0.key) }
    }

    public func icon(for processIdentifier: Int) -> NSImage? {
        if let cachedIcon = icons[processIdentifier] {
            switch cachedIcon {
            case .resolved(let icon):
                return icon
            case .missing:
                return nil
            }
        }

        guard let icon = resolver(processIdentifier) else {
            icons[processIdentifier] = .missing
            return nil
        }

        icons[processIdentifier] = .resolved(icon)
        return icon
    }
}
