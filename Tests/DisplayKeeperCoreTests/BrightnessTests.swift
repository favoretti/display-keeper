import XCTest
@testable import DisplayKeeperCore

final class BrightnessTests: XCTestCase {
    func testDDCWithoutCombinedIsHardwareOnly() {
        let s = BrightnessMix.split(0.3, kind: .ddc, combined: false, allowZero: false)
        XCTAssertEqual(s.hardware, 0.3)
        XCTAssertEqual(s.software, 1)
    }

    func testCombinedUsesSoftwareBelowSwitchPoint() {
        let high = BrightnessMix.split(0.75, kind: .ddc, combined: true, allowZero: false)
        XCTAssertEqual(high.hardware, 0.5)
        XCTAssertEqual(high.software, 1)
        let low = BrightnessMix.split(0.25, kind: .ddc, combined: true, allowZero: true)
        XCTAssertEqual(low.hardware, 0)
        XCTAssertEqual(low.software, 0.5)
    }

    func testSoftwareFloorUnlessZeroAllowed() {
        XCTAssertEqual(BrightnessMix.split(0, kind: .software, combined: false, allowZero: false).software, BrightnessMix.softwareFloor)
        XCTAssertEqual(BrightnessMix.split(0, kind: .software, combined: false, allowZero: true).software, 0)
        XCTAssertEqual(BrightnessMix.split(0, kind: .ddc, combined: true, allowZero: false).software, BrightnessMix.softwareFloor)
    }

    func testAppleIgnoresCombined() {
        let s = BrightnessMix.split(0.2, kind: .apple, combined: true, allowZero: true)
        XCTAssertEqual(s.hardware, 0.2)
        XCTAssertEqual(s.software, 1)
    }

    func testReadBackRoundTripsAndKeepsSoftwarePartAtZero() {
        for v in [0.6, 0.8, 1.0] {
            let h = BrightnessMix.split(v, kind: .ddc, combined: true, allowZero: false).hardware!
            XCTAssertEqual(BrightnessMix.value(hardware: h, kind: .ddc, combined: true, previous: 0), v, accuracy: 1e-9)
        }
        XCTAssertEqual(BrightnessMix.value(hardware: 0, kind: .ddc, combined: true, previous: 0.2), 0.2)
        XCTAssertEqual(BrightnessMix.value(hardware: 0, kind: .ddc, combined: true, previous: 0.9), 0.5)
        XCTAssertEqual(BrightnessMix.value(hardware: 0.4, kind: .ddc, combined: false, previous: 0.9), 0.4)
    }
}
