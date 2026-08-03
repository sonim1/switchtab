import Foundation
import SwitchTab

enum UpdateDiagnosticTests {
    static func run() throws {
        try testClassifiesNetworkFailures()
        try testClassifiesSparkleFailures()
        try testUsesRecognizedUnderlyingError()
        try testFallsBackToUnknownError()
        try testFormatsDeterministicDiagnostic()
        try testDiagnosticExcludesRawPrivateErrorData()
        try testBuildsSupportURLs()
    }

    static func testClassifiesNetworkFailures() throws {
        try expectEqual(
            UpdateErrorClassifier.classify(
                NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
            ).category,
            .connection
        )
        try expectEqual(
            UpdateErrorClassifier.classify(
                NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
            ).category,
            .timeout
        )
        try expectEqual(
            UpdateErrorClassifier.classify(
                NSError(domain: NSURLErrorDomain, code: NSURLErrorSecureConnectionFailed)
            ).category,
            .tls
        )
    }

    static func testClassifiesSparkleFailures() throws {
        try expectEqual(
            UpdateErrorClassifier.classify(
                NSError(domain: "SUSparkleErrorDomain", code: 1000)
            ).category,
            .feed
        )
        try expectEqual(
            UpdateErrorClassifier.classify(
                NSError(domain: "SUSparkleErrorDomain", code: 2001)
            ).category,
            .download
        )
        try expectEqual(
            UpdateErrorClassifier.classify(
                NSError(domain: "SUSparkleErrorDomain", code: 3001)
            ).category,
            .verification
        )
        try expectEqual(
            UpdateErrorClassifier.classify(
                NSError(domain: "SUSparkleErrorDomain", code: 4012)
            ).category,
            .installation
        )
    }

    static func testUsesRecognizedUnderlyingError() throws {
        let underlying = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost)
        let wrapper = NSError(
            domain: "SUSparkleErrorDomain",
            code: 1002,
            userInfo: [NSUnderlyingErrorKey: underlying]
        )

        let result = UpdateErrorClassifier.classify(wrapper)

        try expectEqual(result.category, .connection)
        try expectEqual(result.domain, NSURLErrorDomain)
        try expectEqual(result.code, NSURLErrorCannotConnectToHost)
    }

    static func testFallsBackToUnknownError() throws {
        let result = UpdateErrorClassifier.classify(
            NSError(domain: "ExampleDomain", code: 77)
        )

        try expectEqual(result.category, .unknown)
        try expectEqual(result.domain, "ExampleDomain")
        try expectEqual(result.code, 77)
    }

    static func testFormatsDeterministicDiagnostic() throws {
        let diagnostic = UpdateDiagnostic(
            descriptor: UpdateErrorDescriptor(
                category: .tls,
                domain: NSURLErrorDomain,
                code: NSURLErrorSecureConnectionFailed
            ),
            appVersion: "1.1.0 (11)",
            macOSVersion: "macOS 26.0",
            architecture: "arm64",
            timestamp: Date(timeIntervalSince1970: 1_785_422_400)
        )

        try expectTrue(diagnostic.report.contains("SwitchTab: 1.1.0 (11)"))
        try expectTrue(diagnostic.report.contains("Category: tls"))
        try expectTrue(diagnostic.report.contains("Error: NSURLErrorDomain -1200"))
        try expectFalse(diagnostic.report.contains("Optional"))
    }

    static func testDiagnosticExcludesRawPrivateErrorData() throws {
        let privateURL = "https://updates.example.test/private?employee=kendrick"
        let privatePath = "/Users/example/Secret/update.dmg"
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorCannotConnectToHost,
            userInfo: [
                NSURLErrorFailingURLStringErrorKey: privateURL,
                NSFilePathErrorKey: privatePath,
                NSLocalizedDescriptionKey: "Failed for kendrick at \(privateURL)"
            ]
        )

        let diagnostic = UpdateDiagnostic.make(
            error: error,
            appVersion: "1.1.0 (11)",
            macOSVersion: "macOS 26.0",
            architecture: "arm64",
            timestamp: Date(timeIntervalSince1970: 1_785_422_400)
        )

        try expectFalse(diagnostic.report.contains("kendrick"))
        try expectFalse(diagnostic.report.contains(privateURL))
        try expectFalse(diagnostic.report.contains(privatePath))
    }

    static func testBuildsSupportURLs() throws {
        let diagnostic = UpdateDiagnostic(
            descriptor: UpdateErrorDescriptor(
                category: .connection,
                domain: NSURLErrorDomain,
                code: NSURLErrorNotConnectedToInternet
            ),
            appVersion: "1.1.0 (11)",
            macOSVersion: "macOS 26.0",
            architecture: "arm64",
            timestamp: Date(timeIntervalSince1970: 1_785_422_400)
        )

        try expectEqual(
            UpdateSupportLinks.latestRelease.absoluteString,
            "https://github.com/sonim1/switchtab/releases/latest"
        )
        guard let reportURL = UpdateSupportLinks.reportIssue(for: diagnostic) else {
            throw TestFailure.failed("Expected a report issue URL")
        }
        try expectEqual(reportURL.host, "github.com")
        try expectEqual(reportURL.path, "/sonim1/switchtab/issues/new")
        try expectTrue(reportURL.absoluteString.contains("body="))
    }
}
