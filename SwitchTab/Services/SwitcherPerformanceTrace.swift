import OSLog

struct SwitcherPerformanceInterval {
    let id: OSSignpostID
}

enum SwitcherPerformanceTrace {
    private static let log = OSLog(
        subsystem: "com.royjen.switchtab",
        category: .pointsOfInterest
    )

    static func beginInvocation(mode: SwitcherMode) -> SwitcherPerformanceInterval {
        let interval = SwitcherPerformanceInterval(id: OSSignpostID(log: log))
        os_signpost(
            .begin,
            log: log,
            name: "Switcher Invocation",
            signpostID: interval.id,
            "mode=%{public}s",
            String(describing: mode)
        )
        return interval
    }

    static func endInvocation(_ interval: SwitcherPerformanceInterval, itemCount: Int) {
        os_signpost(
            .end,
            log: log,
            name: "Switcher Invocation",
            signpostID: interval.id,
            "items=%{public}d",
            itemCount
        )
    }

    static func beginAccessibilityDiscovery() -> SwitcherPerformanceInterval {
        let interval = SwitcherPerformanceInterval(id: OSSignpostID(log: log))
        os_signpost(
            .begin,
            log: log,
            name: "Accessibility Discovery",
            signpostID: interval.id
        )
        return interval
    }

    static func endAccessibilityDiscovery(
        _ interval: SwitcherPerformanceInterval,
        itemCount: Int
    ) {
        os_signpost(
            .end,
            log: log,
            name: "Accessibility Discovery",
            signpostID: interval.id,
            "items=%{public}d",
            itemCount
        )
    }

    static func beginApplicationWindowCounts() -> SwitcherPerformanceInterval {
        let interval = SwitcherPerformanceInterval(id: OSSignpostID(log: log))
        os_signpost(
            .begin,
            log: log,
            name: "Application Window Counts",
            signpostID: interval.id
        )
        return interval
    }

    static func endApplicationWindowCounts(
        _ interval: SwitcherPerformanceInterval,
        superseded: Bool
    ) {
        os_signpost(
            .end,
            log: log,
            name: "Application Window Counts",
            signpostID: interval.id,
            "superseded=%{public}d",
            superseded ? 1 : 0
        )
    }

    static func firstThumbnail() {
        os_signpost(.event, log: log, name: "First Thumbnail")
    }
}
