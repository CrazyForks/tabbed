import CoreGraphics
import XCTest
@testable import Tabbed

final class CoordinateConverterTests: XCTestCase {
    func testFrameConversionIsReversible() {
        let appKit = CGRect(x: 10, y: 120, width: 300, height: 200)

        let cg = CoordinateConverter.cgFrame(fromAppKit: appKit, screenHeight: 900)
        XCTAssertEqual(cg, CGRect(x: 10, y: 580, width: 300, height: 200))

        XCTAssertEqual(CoordinateConverter.appKitFrame(fromCG: cg, screenHeight: 900), appKit)
    }

    func testPointConversionFlipsYOnly() {
        let point = CoordinateConverter.appKitPoint(
            fromCG: CGPoint(x: 42, y: 150),
            screenHeight: 900
        )

        XCTAssertEqual(point, CGPoint(x: 42, y: 750))
    }
}
