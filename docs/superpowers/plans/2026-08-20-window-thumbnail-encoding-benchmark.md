# Window Thumbnail Encoding Benchmark Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Measure PNG, JPEG `0.65/0.70/0.75`, and captured-image-first thumbnail pipelines before choosing the persistent cache representation.

**Architecture:** Add a small ImageIO codec that is independently testable, then add an opt-in XCTest benchmark that consumes private local fixtures and writes only ignored evidence. Stop after recording the aggregate decision; persistent-cache and layout product changes belong to a second plan informed by these results.

**Tech Stack:** Swift 6, XCTest, AppKit, CoreGraphics, ImageIO, UniformTypeIdentifiers, existing SwiftPM and Xcode builds.

---

## Scope and File Map

- Create `SwitchTab/Services/WindowThumbnailImageCodec.swift`: native PNG/JPEG encode and decode boundary shared by the benchmark and later product work.
- Modify `SwitchTab.xcodeproj/project.pbxproj`: register the codec in the macOS app target.
- Create `SwitchTabTests/Services/WindowThumbnailImageCodecTests.swift`: codec correctness, dimensions, signatures, and quality-boundary tests.
- Create `SwitchTabTests/Services/WindowThumbnailEncodingBenchmarkTests.swift`: opt-in fixture runner, resize path, timing aggregation, sample output, and JSON result writing.
- Modify `docs/superpowers/specs/2026-08-20-persistent-window-thumbnail-cache-design.md`: append aggregate benchmark results and the chosen pipeline; never add fixture names or image bytes.
- Write ignored local artifacts under `.omo/evidence/window-thumbnail-encoding/`: private fixtures, encoded samples, raw JSON, command logs, and visual-review notes.

No cache lifetime, loader behavior, overlay layout, or production format changes occur in this plan.

### Task 1: Add a native, testable PNG/JPEG codec

**Files:**
- Create: `SwitchTab/Services/WindowThumbnailImageCodec.swift`
- Create: `SwitchTabTests/Services/WindowThumbnailImageCodecTests.swift`
- Modify: `SwitchTab.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing codec tests**

Create a native XCTest case so SwiftPM discovers it automatically:

```swift
import CoreGraphics
import XCTest
@testable import SwitchTab

@MainActor
final class WindowThumbnailImageCodecTests: XCTestCase {
    func testPNGAndJPEGEncodeToDecodableImagesWithOriginalDimensions() throws {
        let image = try makeImage(width: 64, height: 40)

        let png = try XCTUnwrap(WindowThumbnailImageCodec.encode(image, as: .png))
        let jpeg = try XCTUnwrap(WindowThumbnailImageCodec.encode(image, as: .jpeg(quality: 0.70)))

        XCTAssertEqual(Array(png.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
        XCTAssertEqual(Array(jpeg.prefix(2)), [0xff, 0xd8])

        let decodedPNG = try XCTUnwrap(WindowThumbnailImageCodec.decode(png))
        let decodedJPEG = try XCTUnwrap(WindowThumbnailImageCodec.decode(jpeg))
        XCTAssertEqual(decodedPNG.width, 64)
        XCTAssertEqual(decodedPNG.height, 40)
        XCTAssertEqual(decodedJPEG.width, 64)
        XCTAssertEqual(decodedJPEG.height, 40)
    }

    func testJPEGQualityIsClampedToImageIODomain() throws {
        let image = try makeImage(width: 32, height: 20)
        XCTAssertNotNil(WindowThumbnailImageCodec.encode(image, as: .jpeg(quality: -1)))
        XCTAssertNotNil(WindowThumbnailImageCodec.encode(image, as: .jpeg(quality: 2)))
    }

    private func makeImage(width: Int, height: Int) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.08, green: 0.12, blue: 0.18, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0.9, green: 0.6, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 4, y: 4, width: width / 2, height: height / 3))
        return try XCTUnwrap(context.makeImage())
    }
}
```

- [ ] **Step 2: Run the focused tests to prove RED**

Run:

```bash
rtk swift test --filter WindowThumbnailImageCodecTests
```

Expected: compile failure because `WindowThumbnailImageCodec` and `WindowThumbnailEncodingFormat` do not exist. Save the output to `.omo/evidence/window-thumbnail-encoding/task1-red.log`.

- [ ] **Step 3: Implement the minimal codec**

Create `WindowThumbnailImageCodec.swift`:

```swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum WindowThumbnailEncodingFormat: Equatable, Sendable {
    case png
    case jpeg(quality: Double)
}

enum WindowThumbnailImageCodec {
    static func encode(
        _ image: CGImage,
        as format: WindowThumbnailEncodingFormat
    ) -> Data? {
        let data = NSMutableData()
        let type: UTType
        let properties: CFDictionary?

        switch format {
        case .png:
            type = .png
            properties = nil
        case .jpeg(let quality):
            type = .jpeg
            properties = [
                kCGImageDestinationLossyCompressionQuality:
                    min(1, max(0, quality))
            ] as CFDictionary
        }

        guard let destination = CGImageDestinationCreateWithData(
            data,
            type.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return data as Data
    }

    static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
```

Register this file in the Xcode project's Services group and the app target's Sources phase, following the existing `SwitcherPerformanceTrace.swift` entries exactly.

- [ ] **Step 4: Run focused and full verification**

Run:

```bash
rtk swift test --filter WindowThumbnailImageCodecTests
rtk swift test
rtk swift build
rtk proxy env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project SwitchTab.xcodeproj -scheme SwitchTab \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO build
rtk git diff --check
```

Expected: codec tests pass, full suite reports zero failures, both builds succeed, and diff check is clean.

- [ ] **Step 5: Commit the codec**

```bash
rtk git add SwitchTab/Services/WindowThumbnailImageCodec.swift \
  SwitchTabTests/Services/WindowThumbnailImageCodecTests.swift \
  SwitchTab.xcodeproj/project.pbxproj
rtk git commit -m "test: add thumbnail image codec benchmark boundary"
```

### Task 2: Add an opt-in benchmark runner

**Files:**
- Create: `SwitchTabTests/Services/WindowThumbnailEncodingBenchmarkTests.swift`

- [ ] **Step 1: Write the benchmark contract test first**

The default contract uses an in-memory fixture and proves all candidates produce
decodable output and timing samples. The private-fixture benchmark remains opt-in.

```swift
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
        XCTAssertTrue(result.candidates.allSatisfy { $0.encodedByteMedian >= 0 })
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
```

- [ ] **Step 2: Run the focused test to prove RED**

Run:

```bash
rtk swift test --filter WindowThumbnailEncodingBenchmarkTests/testRunnerProducesAllEncodingCandidates
```

Expected: compile failure because `BenchmarkFixture` and `ThumbnailEncodingBenchmark` do not exist. Save output to `.omo/evidence/window-thumbnail-encoding/task2-red.log`.

- [ ] **Step 3: Implement test-only benchmark types in the same file**

Add private types below the XCTest case:

```swift
private struct BenchmarkFixture {
    let name: String
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
        return BenchmarkFixture(name: "synthetic", image: try XCTUnwrap(context.makeImage()))
    }

    static func loadImages(in directory: URL) throws -> [BenchmarkFixture] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { ["png", "jpg", "jpeg", "heic"].contains($0.pathExtension.lowercased()) }

        return try urls.sorted { $0.lastPathComponent < $1.lastPathComponent }.map { url in
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            return BenchmarkFixture(name: url.deletingPathExtension().lastPathComponent, image: image)
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
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(BenchmarkReport(candidates: candidates)).write(
            to: directory.appendingPathComponent("results.json")
        )
        for artifact in artifacts {
            try artifact.data.write(to: directory.appendingPathComponent(artifact.filename))
        }
    }
}
```

Implement `ThumbnailEncodingBenchmark.run` with these types and control flow:

```swift
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
        Candidate(name: "jpeg-0.65", format: .jpeg(quality: 0.65), rawFirst: false, fileExtension: "jpg"),
        Candidate(name: "jpeg-0.70", format: .jpeg(quality: 0.70), rawFirst: false, fileExtension: "jpg"),
        Candidate(name: "jpeg-0.75", format: .jpeg(quality: 0.75), rawFirst: false, fileExtension: "jpg"),
        Candidate(name: "raw-first", format: .jpeg(quality: 0.70), rawFirst: true, fileExtension: "jpg")
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
                    samples[candidate.name]?.decodedRGBABytes.append(image.width * image.height * 4)
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
            let data = try XCTUnwrap(WindowThumbnailImageCodec.encode(image, as: candidate.format))
            let encode = DispatchTime.now().uptimeNanoseconds - encodeStart

            let decodeStart = DispatchTime.now().uptimeNanoseconds
            let decoded = try XCTUnwrap(WindowThumbnailImageCodec.decode(data))
            let cachedImage = NSImage(cgImage: decoded, size: .zero)
            withExtendedLifetime(cachedImage) {}
            let decode = DispatchTime.now().uptimeNanoseconds - decodeStart
            return (firstDisplay, encode, decode, data)
        }

        let firstStart = DispatchTime.now().uptimeNanoseconds
        let encodeStart = firstStart
        let data = try XCTUnwrap(WindowThumbnailImageCodec.encode(image, as: candidate.format))
        let encodeEnd = DispatchTime.now().uptimeNanoseconds
        let decoded = try XCTUnwrap(WindowThumbnailImageCodec.decode(data))
        let cachedImage = NSImage(cgImage: decoded, size: .zero)
        withExtendedLifetime(cachedImage) {}
        let end = DispatchTime.now().uptimeNanoseconds
        return (end - firstStart, encodeEnd - encodeStart, end - encodeEnd, data)
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
        context.draw(source, in: CGRect(x: 0, y: 0, width: target.width, height: target.height))
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
```

The implementation must preserve these measurement rules:

- resize each fixture to the existing `WindowThumbnailCaptureSizing.targetPixelSize`
  using viewport `288 x 198`, derived from `192 x 132 pt * 1.5`;
- execute 5 unrecorded warmups and 30 measured iterations for private fixtures;
- time with `DispatchTime.now().uptimeNanoseconds`;
- for PNG and JPEG candidates, define first-display time as encode plus decode plus
  `NSImage(cgImage:size:)` conversion;
- for `raw-first`, define first-display time as only `NSImage(cgImage:size:)`, while
  separately recording JPEG `0.70` background encoding;
- calculate median by sorted middle element and p95 by index
  `min(count - 1, Int((Double(count) * 0.95).rounded(.up)) - 1)`;
- write one encoded sample per fixture and format to the configured output directory;
- never print fixture paths, names, titles, image bytes, or process identifiers.

Use a local `autoreleasepool` around every iteration so decoded images from prior
iterations do not contaminate later memory or latency measurements.

- [ ] **Step 4: Run the contract and full suite**

Run:

```bash
rtk swift test --filter WindowThumbnailEncodingBenchmarkTests/testRunnerProducesAllEncodingCandidates
rtk swift test
rtk git diff --check
```

Expected: contract passes; the private benchmark reports one intentional skip when environment variables are absent; all other tests pass.

- [ ] **Step 5: Commit the benchmark runner**

```bash
rtk git add SwitchTabTests/Services/WindowThumbnailEncodingBenchmarkTests.swift
rtk git commit -m "test: benchmark thumbnail encoding pipelines"
```

### Task 3: Run private native measurements and choose the pipeline

**Files:**
- Create ignored evidence only: `.omo/evidence/window-thumbnail-encoding/**`

- [ ] **Step 1: Capture four representative private fixtures**

Create the ignored directories and use macOS interactive window capture so no
window identifiers or names enter command logs:

```bash
rtk proxy mkdir -p .omo/evidence/window-thumbnail-encoding/fixtures
rtk proxy mkdir -p .omo/evidence/window-thumbnail-encoding/output
rtk proxy screencapture -i .omo/evidence/window-thumbnail-encoding/fixtures/fixture-1.png
rtk proxy screencapture -i .omo/evidence/window-thumbnail-encoding/fixtures/fixture-2.png
rtk proxy screencapture -i .omo/evidence/window-thumbnail-encoding/fixtures/fixture-3.png
rtk proxy screencapture -i .omo/evidence/window-thumbnail-encoding/fixtures/fixture-4.png
```

Choose one light text-heavy window, one dark text-heavy window, one image-heavy
window, and one mixed UI window. Verify `.omo/evidence` is ignored before saving.

- [ ] **Step 2: Run the benchmark twice**

Run two independent 30-iteration passes:

```bash
rtk proxy env \
  SWITCHTAB_THUMBNAIL_BENCHMARK_INPUT_DIR="$PWD/.omo/evidence/window-thumbnail-encoding/fixtures" \
  SWITCHTAB_THUMBNAIL_BENCHMARK_OUTPUT_DIR="$PWD/.omo/evidence/window-thumbnail-encoding/output/run-1" \
  rtk swift test --filter WindowThumbnailEncodingBenchmarkTests/testPrivateFixtureBenchmarkWhenConfigured

rtk proxy env \
  SWITCHTAB_THUMBNAIL_BENCHMARK_INPUT_DIR="$PWD/.omo/evidence/window-thumbnail-encoding/fixtures" \
  SWITCHTAB_THUMBNAIL_BENCHMARK_OUTPUT_DIR="$PWD/.omo/evidence/window-thumbnail-encoding/output/run-2" \
  rtk swift test --filter WindowThumbnailEncodingBenchmarkTests/testPrivateFixtureBenchmarkWhenConfigured
```

Expected: both runs pass, each result has four fixtures and 30 samples per
candidate, and no fixture path or name appears in stdout.

- [ ] **Step 3: Inspect visual candidates**

Open the generated PNG and JPEG `0.65/0.70/0.75` samples at `192 x 132 pt`
equivalent and at 2x zoom. Record only these judgments in
`.omo/evidence/window-thumbnail-encoding/visual-review.md`:

```markdown
| Candidate | Text edges | Thin rules | Dark gradients | Shadows | Acceptable |
|---|---|---|---|---|---|
| PNG | pass/fail | pass/fail | pass/fail | pass/fail | yes/no |
| JPEG 0.65 | pass/fail | pass/fail | pass/fail | pass/fail | yes/no |
| JPEG 0.70 | pass/fail | pass/fail | pass/fail | pass/fail | yes/no |
| JPEG 0.75 | pass/fail | pass/fail | pass/fail | pass/fail | yes/no |
```

Do not embed or commit screenshots.

- [ ] **Step 4: Apply the decision rules**

Write `.omo/evidence/window-thumbnail-encoding/decision.md` with aggregate run-1
and run-2 median/p95, encoded-byte medians, and the selected pipeline.

Choose:

- `raw-first + JPEG <quality>` only if raw-first has lower median first-display
  time with no p95 regression, the quality is visually acceptable, and JPEG has
  material byte or background-encode benefit;
- `raw-first + PNG` if raw-first wins latency but all JPEG qualities fail the
  visual/material-benefit gate;
- existing encode-first PNG or JPEG only if raw-first fails its latency/p95 gate.

Stop and report the measurements instead of silently relaxing a gate.

### Task 4: Record the benchmark decision and verify the branch

**Files:**
- Modify: `docs/superpowers/specs/2026-08-20-persistent-window-thumbnail-cache-design.md`

- [ ] **Step 1: Add the aggregate result to the design**

Append a `## Benchmark Result` section containing:

- test date and machine architecture, without username or local path;
- fixture categories, iteration and warmup counts;
- run-1 and run-2 median/p95 table;
- median encoded bytes and decoded RGBA estimate;
- visual pass/fail table without screenshots;
- selected pipeline and the exact decision-rule evidence.

Do not modify the design's cache limits or layout decision in this task.

- [ ] **Step 2: Run complete verification**

```bash
rtk swift test
rtk swift build
rtk proxy env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project SwitchTab.xcodeproj -scheme SwitchTab \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO build
rtk git diff --check
rtk git status --short
```

Expected: all tests and builds pass, diff check is clean, and only the design
document remains uncommitted. `.omo/evidence` stays ignored.

- [ ] **Step 3: Commit the aggregate decision**

```bash
rtk git add docs/superpowers/specs/2026-08-20-persistent-window-thumbnail-cache-design.md
rtk git commit -m "docs: record thumbnail encoding benchmark"
rtk git status --short
```

Expected: clean worktree. Do not begin the persistent cache implementation.

- [ ] **Step 4: Present the result gate to the user**

Report the measured pipeline, median/p95, byte reduction, visual outcome, and any
regression. Ask for approval before writing the separate persistent-cache and
`192 x 132 pt` layout implementation plan.
