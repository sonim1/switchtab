import Foundation

enum TestFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message): return message
        }
    }
}

func expectTrue(
    _ condition: Bool,
    _ message: String? = nil,
    file: StaticString = #fileID,
    line: UInt = #line
) throws {
    guard condition else {
        throw TestFailure.failed(message ?? "Expected true at \(file):\(line)")
    }
}

func expectFalse(
    _ condition: Bool,
    _ message: String? = nil,
    file: StaticString = #fileID,
    line: UInt = #line
) throws {
    guard !condition else {
        throw TestFailure.failed(message ?? "Expected false at \(file):\(line)")
    }
}

func expectEqual<T: Equatable>(
    _ actual: T,
    _ expected: T,
    _ message: String? = nil,
    file: StaticString = #fileID,
    line: UInt = #line
) throws {
    guard actual == expected else {
        throw TestFailure.failed(message ?? "Expected \(expected), got \(actual) at \(file):\(line)")
    }
}
