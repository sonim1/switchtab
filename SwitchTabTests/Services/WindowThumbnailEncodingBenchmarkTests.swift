import AppKit
import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import SwitchTab

@MainActor
final class WindowThumbnailEncodingBenchmarkTests: XCTestCase {
    func testRunnerProducesAllEncodingCandidates() throws {
        let fixture = try BenchmarkFixture.synthetic(width: 288, height: 198)
        let result = try ThumbnailEncodingBenchmark.run(
            fixtures: [fixture],
            warmupIterations: 1,
            measuredIterations: 2
        )

        XCTAssertEqual(Set(result.candidates.map(\.name)), [
            "png", "jpeg-0.65", "jpeg-0.70", "jpeg-0.75", "raw-first"
        ])
        XCTAssertTrue(result.candidates.allSatisfy { $0.sampleCount == 2 })
        XCTAssertTrue(result.candidates.allSatisfy { $0.encodedByteMedian > 0 })
        XCTAssertTrue(result.candidates.allSatisfy { $0.firstDisplayMedianNanoseconds > 0 })
        XCTAssertTrue(result.candidates.allSatisfy { $0.encodeMedianNanoseconds > 0 })
        XCTAssertTrue(result.candidates.allSatisfy { $0.decodeMedianNanoseconds > 0 })
    }

    func testPrivateFixtureBenchmarkWhenConfigured() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let inputDirectory = environment["SWITCHTAB_THUMBNAIL_BENCHMARK_INPUT_DIR"],
              let outputDirectory = environment["SWITCHTAB_THUMBNAIL_BENCHMARK_OUTPUT_DIR"] else {
            throw XCTSkip("Set benchmark input and output directories to run private fixtures")
        }

        let fixtures = try BenchmarkFixture.loadImages(in: URL(fileURLWithPath: inputDirectory))
        XCTAssertGreaterThanOrEqual(fixtures.count, 4)
        let result = try ThumbnailEncodingBenchmark.run(
            fixtures: fixtures,
            warmupIterations: 5,
            measuredIterations: 30
        )
        try result.writeArtifacts(to: URL(fileURLWithPath: outputDirectory))
    }
}

private struct BenchmarkFixture {
    let image: CGImage

    static func synthetic(width: Int, height: Int) throws -> BenchmarkFixture {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for index in 0..<12 {
            context.setStrokeColor(CGColor(gray: CGFloat(index + 2) / 14, alpha: 1))
            context.move(to: CGPoint(x: 8, y: 10 + index * 12))
            context.addLine(to: CGPoint(x: width - 8, y: 10 + index * 12))
            context.strokePath()
        }
        return BenchmarkFixture(image: try XCTUnwrap(context.makeImage()))
    }

    static func loadImages(in directory: URL) throws -> [BenchmarkFixture] {
        let supportedExtensions = Set(["png", "jpg", "jpeg", "heic"])
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { supportedExtensions.contains($0.pathExtension.lowercased()) }

        return try urls.sorted { $0.lastPathComponent < $1.lastPathComponent }.map { url in
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
            return BenchmarkFixture(
                image: try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            )
        }
    }
}

private struct BenchmarkCandidateResult: Codable {
    let name: String
    let sampleCount: Int
    let firstDisplayMedianNanoseconds: UInt64
    let firstDisplayP95Nanoseconds: UInt64
    let encodeMedianNanoseconds: UInt64
    let encodeP95Nanoseconds: UInt64
    let decodeMedianNanoseconds: UInt64
    let decodeP95Nanoseconds: UInt64
    let encodedByteMedian: Int
    let decodedRGBABytes: Int
}

private struct BenchmarkArtifact {
    let filename: String
    let data: Data
}

private struct BenchmarkReport: Codable {
    let candidates: [BenchmarkCandidateResult]
}

private struct ThumbnailEncodingBenchmarkResult {
    let candidates: [BenchmarkCandidateResult]
    let artifacts: [BenchmarkArtifact]

    func writeArtifacts(to directory: URL) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(BenchmarkReport(candidates: candidates)).write(
            to: directory.appendingPathComponent("results.json"),
            options: .atomic
        )
        for artifact in artifacts {
            try artifact.data.write(
                to: directory.appendingPathComponent(artifact.filename),
                options: .atomic
            )
        }
    }
}

@MainActor
private enum ThumbnailEncodingBenchmark {
    private struct Candidate {
        let name: String
        let format: WindowThumbnailEncodingFormat
        let rawFirst: Bool
        let fileExtension: String
    }

    private struct Samples {
        var firstDisplay: [UInt64] = []
        var encode: [UInt64] = []
        var decode: [UInt64] = []
        var bytes: [Int] = []
        var decodedRGBABytes: [Int] = []
    }

    private static let candidates = [
        Candidate(name: "png", format: .png, rawFirst: false, fileExtension: "png"),
        Candidate(
            name: "jpeg-0.65",
            format: .jpeg(quality: 0.65),
            rawFirst: false,
            fileExtension: "jpg"
        ),
        Candidate(
            name: "jpeg-0.70",
            format: .jpeg(quality: 0.70),
            rawFirst: false,
            fileExtension: "jpg"
        ),
        Candidate(
            name: "jpeg-0.75",
            format: .jpeg(quality: 0.75),
            rawFirst: false,
            fileExtension: "jpg"
        ),
        Candidate(
            name: "raw-first",
            format: .jpeg(quality: 0.70),
            rawFirst: true,
            fileExtension: "jpg"
        )
    ]

    static func run(
        fixtures: [BenchmarkFixture],
        warmupIterations: Int,
        measuredIterations: Int
    ) throws -> ThumbnailEncodingBenchmarkResult {
        precondition(!fixtures.isEmpty)
        precondition(warmupIterations >= 0)
        precondition(measuredIterations > 0)

        var samples = Dictionary(
            uniqueKeysWithValues: candidates.map { ($0.name, Samples()) }
        )
        var artifacts: [BenchmarkArtifact] = []

        for (fixtureIndex, fixture) in fixtures.enumerated() {
            let image = try resized(fixture.image)
            for candidate in candidates {
                for _ in 0..<warmupIterations {
                    _ = try autoreleasepool {
                        try measureOne(image: image, candidate: candidate)
                    }
                }

                for _ in 0..<measuredIterations {
                    let measurement = try autoreleasepool {
                        try measureOne(image: image, candidate: candidate)
                    }
                    samples[candidate.name]?.firstDisplay.append(measurement.firstDisplay)
                    samples[candidate.name]?.encode.append(measurement.encode)
                    samples[candidate.name]?.decode.append(measurement.decode)
                    samples[candidate.name]?.bytes.append(measurement.data.count)
                    samples[candidate.name]?.decodedRGBABytes.append(
                        image.width * image.height * 4
                    )
                }

                let sampleData = try XCTUnwrap(
                    WindowThumbnailImageCodec.encode(image, as: candidate.format)
                )
                artifacts.append(BenchmarkArtifact(
                    filename: "sample-\(fixtureIndex + 1)-\(candidate.name).\(candidate.fileExtension)",
                    data: sampleData
                ))
            }
        }

        let results = try candidates.map { candidate -> BenchmarkCandidateResult in
            let values = try XCTUnwrap(samples[candidate.name])
            return BenchmarkCandidateResult(
                name: candidate.name,
                sampleCount: values.firstDisplay.count,
                firstDisplayMedianNanoseconds: percentile(values.firstDisplay, 0.50),
                firstDisplayP95Nanoseconds: percentile(values.firstDisplay, 0.95),
                encodeMedianNanoseconds: percentile(values.encode, 0.50),
                encodeP95Nanoseconds: percentile(values.encode, 0.95),
                decodeMedianNanoseconds: percentile(values.decode, 0.50),
                decodeP95Nanoseconds: percentile(values.decode, 0.95),
                encodedByteMedian: percentile(values.bytes, 0.50),
                decodedRGBABytes: percentile(values.decodedRGBABytes, 0.50)
            )
        }
        return ThumbnailEncodingBenchmarkResult(candidates: results, artifacts: artifacts)
    }

    private static func measureOne(
        image: CGImage,
        candidate: Candidate
    ) throws -> (firstDisplay: UInt64, encode: UInt64, decode: UInt64, data: Data) {
        if candidate.rawFirst {
            let displayStart = DispatchTime.now().uptimeNanoseconds
            let displayImage = NSImage(cgImage: image, size: .zero)
            withExtendedLifetime(displayImage) {}
            let firstDisplay = DispatchTime.now().uptimeNanoseconds - displayStart

            let encodeStart = DispatchTime.now().uptimeNanoseconds
            let data = try XCTUnwrap(
                WindowThumbnailImageCodec.encode(image, as: candidate.format)
            )
            let encode = DispatchTime.now().uptimeNanoseconds - encodeStart

            let decodeStart = DispatchTime.now().uptimeNanoseconds
            let decoded = try XCTUnwrap(WindowThumbnailImageCodec.decode(data))
            let cachedImage = NSImage(cgImage: decoded, size: .zero)
            withExtendedLifetime(cachedImage) {}
            let decode = DispatchTime.now().uptimeNanoseconds - decodeStart
            return (firstDisplay, encode, decode, data)
        }

        let firstStart = DispatchTime.now().uptimeNanoseconds
        let data = try XCTUnwrap(
            WindowThumbnailImageCodec.encode(image, as: candidate.format)
        )
        let encodeEnd = DispatchTime.now().uptimeNanoseconds
        let decoded = try XCTUnwrap(WindowThumbnailImageCodec.decode(data))
        let cachedImage = NSImage(cgImage: decoded, size: .zero)
        withExtendedLifetime(cachedImage) {}
        let end = DispatchTime.now().uptimeNanoseconds
        return (end - firstStart, encodeEnd - firstStart, end - encodeEnd, data)
    }

    private static func resized(_ source: CGImage) throws -> CGImage {
        let target = WindowThumbnailCaptureSizing.targetPixelSize(
            for: CGRect(x: 0, y: 0, width: source.width, height: source.height),
            viewportPixelSize: CGSize(width: 288, height: 198)
        )
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: target.width,
            height: target.height,
            bitsPerComponent: 8,
            bytesPerRow: target.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.interpolationQuality = .high
        context.draw(
            source,
            in: CGRect(x: 0, y: 0, width: target.width, height: target.height)
        )
        return try XCTUnwrap(context.makeImage())
    }

    private static func percentile<T: Comparable>(_ values: [T], _ fraction: Double) -> T {
        precondition(!values.isEmpty)
        let sorted = values.sorted()
        let index = min(
            sorted.count - 1,
            max(0, Int((Double(sorted.count) * fraction).rounded(.up)) - 1)
        )
        return sorted[index]
    }
}
