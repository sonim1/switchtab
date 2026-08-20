import CoreGraphics
import XCTest
@testable import SwitchTab

@MainActor
final class WindowThumbnailImageCodecTests: XCTestCase {
    func testPNGAndJPEGEncodeToDecodableImagesWithOriginalDimensions() throws {
        let image = try makeImage(width: 64, height: 40)

        let png = try XCTUnwrap(WindowThumbnailImageCodec.encode(image, as: .png))
        let jpeg = try XCTUnwrap(
            WindowThumbnailImageCodec.encode(image, as: .jpeg(quality: 0.70))
        )

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
