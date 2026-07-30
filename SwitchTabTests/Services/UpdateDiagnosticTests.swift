import Foundation
import SwitchTab

enum UpdateDiagnosticTests {
    static func run() throws {
        try testClassifiesNetworkFailures()
        try testClassifiesSparkleFailures()
        try testUsesRecognizedUnderlyingError()
        try testFallsBackToUnknownError()
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
}
