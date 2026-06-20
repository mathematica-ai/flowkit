import XCTest
@testable import LangflowKit

#if canImport(Vision)
import ImageIO
import CoreGraphics

final class VisionOCRTests: XCTestCase {
    func testNoImagesReturnsSentinel() async throws {
        let out = try await VisionOCRTool(images: []).call("")
        XCTAssertTrue(out.contains("No images"))
    }

    func testRunsPipelineOnImageWithoutThrowing() async throws {
        let png = Self.makeSolidPNG(width: 80, height: 40)
        let out = try await VisionOCRTool(images: [png]).call("")
        XCTAssertTrue(out.contains("[image 0]"), "OCR pipeline should run per image: \(out)")
    }

    private static func makeSolidPNG(width: Int, height: Int) -> Data {
        let space = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = ctx.makeImage()!
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out as CFMutableData, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        return out as Data
    }
}
#endif
