import Foundation

public enum UpdateFailureCategory: String, Equatable, Sendable {
    case connection
    case timeout
    case tls
    case feed
    case download
    case verification
    case installation
    case unknown

    public var stage: String {
        switch self {
        case .connection, .timeout, .tls, .feed: "Feed download"
        case .download: "Update download"
        case .verification: "Update verification"
        case .installation: "Update installation"
        case .unknown: "Update check"
        }
    }

    public var title: String {
        switch self {
        case .connection, .timeout, .tls: "Unable to Connect to the Update Server"
        case .feed: "Unable to Read Update Information"
        case .download: "Unable to Download the Update"
        case .verification: "Unable to Verify the Update"
        case .installation: "Unable to Install the Update"
        case .unknown: "Unable to Check for Updates"
        }
    }

    public var explanation: String {
        switch self {
        case .connection:
            "Your network, VPN, or security proxy may be blocking the connection."
        case .timeout:
            "The update server took too long to respond. Check your connection and try again."
        case .tls:
            "A secure connection could not be established. A VPN or security proxy may be inspecting the connection."
        case .feed:
            "SwitchTab received update information it could not read."
        case .download:
            "The update file could not be downloaded."
        case .verification:
            "The downloaded update did not pass SwitchTab's security checks."
        case .installation:
            "The update could not be installed. Check that SwitchTab is in Applications and is writable."
        case .unknown:
            "An unexpected updater error occurred."
        }
    }
}

public struct UpdateErrorDescriptor: Equatable, Sendable {
    public let category: UpdateFailureCategory
    public let domain: String
    public let code: Int

    public init(category: UpdateFailureCategory, domain: String, code: Int) {
        self.category = category
        self.domain = domain
        self.code = code
    }

    public var technicalSummary: String {
        "\(category.stage) · \(domain) \(code)"
    }
}

public enum UpdateErrorClassifier {
    public static func classify(_ error: NSError) -> UpdateErrorDescriptor {
        var current: NSError? = error
        var fallback = descriptor(for: error)
        var recognizedFallback: UpdateErrorDescriptor?
        var visited = Set<ObjectIdentifier>()

        while let candidate = current,
              visited.insert(ObjectIdentifier(candidate)).inserted {
            let descriptor = descriptor(for: candidate)
            if descriptor.category != .unknown {
                if candidate.domain == NSURLErrorDomain {
                    return descriptor
                }
                if recognizedFallback == nil {
                    recognizedFallback = descriptor
                }
            }
            fallback = descriptor
            current = candidate.userInfo[NSUnderlyingErrorKey] as? NSError
        }

        return recognizedFallback ?? fallback
    }

    private static func descriptor(for error: NSError) -> UpdateErrorDescriptor {
        let category: UpdateFailureCategory
        if error.domain == NSURLErrorDomain {
            switch error.code {
            case NSURLErrorNotConnectedToInternet,
                 NSURLErrorCannotFindHost,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorNetworkConnectionLost:
                category = .connection
            case NSURLErrorTimedOut:
                category = .timeout
            case NSURLErrorSecureConnectionFailed,
                 NSURLErrorServerCertificateHasBadDate,
                 NSURLErrorServerCertificateUntrusted,
                 NSURLErrorServerCertificateNotYetValid,
                 NSURLErrorClientCertificateRejected,
                 NSURLErrorClientCertificateRequired:
                category = .tls
            default:
                category = .unknown
            }
        } else if error.domain == "SUSparkleErrorDomain" {
            switch error.code {
            case 3, 4, 1000, 1002, 1004:
                category = .feed
            case 2000, 2001:
                category = .download
            case 3000, 3001, 3002:
                category = .verification
            case 4000 ... 4012:
                category = .installation
            default:
                category = .unknown
            }
        } else {
            category = .unknown
        }

        return UpdateErrorDescriptor(category: category, domain: error.domain, code: error.code)
    }
}

public struct UpdateDiagnostic: Equatable, Sendable {
    public let descriptor: UpdateErrorDescriptor
    public let appVersion: String
    public let macOSVersion: String
    public let architecture: String
    public let timestamp: Date

    public init(
        descriptor: UpdateErrorDescriptor,
        appVersion: String,
        macOSVersion: String,
        architecture: String,
        timestamp: Date
    ) {
        self.descriptor = descriptor
        self.appVersion = appVersion
        self.macOSVersion = macOSVersion
        self.architecture = architecture
        self.timestamp = timestamp
    }

    public static func make(
        error: NSError,
        appVersion: String = ApplicationVersionProvider.currentVersionDisplay(),
        macOSVersion: String = ProcessInfo.processInfo.operatingSystemVersionString,
        architecture: String? = nil,
        timestamp: Date = Date()
    ) -> UpdateDiagnostic {
        UpdateDiagnostic(
            descriptor: UpdateErrorClassifier.classify(error),
            appVersion: appVersion,
            macOSVersion: macOSVersion,
            architecture: architecture ?? currentArchitecture,
            timestamp: timestamp
        )
    }

    public var report: String {
        let date = ISO8601DateFormatter().string(from: timestamp)
        return """
        SwitchTab Update Diagnostic
        SwitchTab: \(appVersion)
        macOS: \(macOSVersion)
        Architecture: \(architecture)
        Stage: \(descriptor.category.stage)
        Category: \(descriptor.category.rawValue)
        Error: \(descriptor.domain) \(descriptor.code)
        Time: \(date)
        """
    }

    private static var currentArchitecture: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unknown"
        #endif
    }
}

public enum UpdateSupportLinks {
    public static let latestRelease = URL(
        string: "https://github.com/sonim1/switchtab/releases/latest"
    )!

    public static func reportIssue(for diagnostic: UpdateDiagnostic) -> URL? {
        var components = URLComponents(
            string: "https://github.com/sonim1/switchtab/issues/new"
        )
        components?.queryItems = [
            URLQueryItem(
                name: "title",
                value: "Update failure: \(diagnostic.descriptor.category.rawValue)"
            ),
            URLQueryItem(
                name: "body",
                value: """
                ## What happened?

                Describe your network, VPN, and the steps that reproduced the error.

                ## Diagnostic information

                \(diagnostic.report)
                """
            )
        ]
        return components?.url
    }
}
