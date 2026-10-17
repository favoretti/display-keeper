import XCTest
@testable import DisplayKeeperCore

final class IdentityTests: XCTestCase {
    func raw(serial: UInt32 = 810634570, alnum: String? = nil, port: String? = nil, builtin: Bool = false,
             uuid: String = UUID().uuidString) -> RawIdentity {
        RawIdentity(vendor: 0x4c2d, model: 0x0e00, edidSerial: serial, alphanumericSerial: alnum,
                    port: port, isBuiltin: builtin, uuid: uuid)
    }

    func testBuiltinIsAlwaysBuiltin() {
        XCTAssertEqual(IdentityResolver.keys(for: [raw(builtin: true)]), ["builtin"])
    }

    func testTwinsUseAlphanumericSerial() {
        let keys = IdentityResolver.keys(for: [raw(alnum: "HTPM100050"), raw(alnum: "HTPM100061")])
        XCTAssertEqual(keys, ["4c2d-0e00-HTPM100050", "4c2d-0e00-HTPM100061"])
    }

    func testUniqueEdidSerialIsEnough() {
        XCTAssertEqual(IdentityResolver.keys(for: [raw(serial: 1), raw(serial: 2)]), ["4c2d-0e00-1", "4c2d-0e00-2"])
    }

    func testTwinsWithoutSerialFallBackToPort() {
        let keys = IdentityResolver.keys(for: [raw(port: "dispext0"), raw(port: "dispext1")])
        XCTAssertEqual(keys, ["4c2d-0e00@dispext0", "4c2d-0e00@dispext1"])
    }

    func testKeysStayUniqueInWorstCase() {
        let keys = IdentityResolver.keys(for: [raw(port: "x"), raw(port: "x")])
        XCTAssertEqual(Set(keys).count, 2)
    }

    func testPortName() {
        XCTAssertEqual(IdentityResolver.portName(fromLocation:
            "IOService:/AppleARMPE/arm-io@10F00000/AppleSoCIO/dispext1@90000000/IOMobileFramebufferShim"), "dispext1")
    }
}

final class ProfileTests: XCTestCase {
    let mode = DisplayMode(width: 3360, height: 1890, pixelWidth: 6720, pixelHeight: 3780, refreshRate: 60)

    func place(_ key: String, _ x: Int) -> Placement { Placement(key: key, name: key, x: x, y: -1890, mode: mode) }

    func testIdIgnoresOrder() {
        XCTAssertEqual(Profile.id(for: ["b", "a"]), Profile.id(for: ["a", "b"]))
    }

    func testSwappedMonitorsAreDetected() {
        let saved = Profile(placements: [place("a", 1099), place("b", -2261)])
        let diff = saved.differences(from: [place("a", -2261), place("b", 1099)])
        XCTAssertEqual(diff?.map(\.key), ["a", "b"])
    }

    func testMatchingLayoutHasNoDifferences() {
        let saved = Profile(placements: [place("a", 1099), place("b", -2261)])
        XCTAssertEqual(saved.differences(from: [place("b", -2261), place("a", 1099)]), [])
    }

    func testDifferentMonitorSetIsNotOurs() {
        let saved = Profile(placements: [place("a", 0), place("b", 0)])
        XCTAssertNil(saved.differences(from: [place("a", 0), place("c", 0)]))
    }

    func testBestModePrefersExactThenClosestRefresh() {
        var m50 = mode; m50.refreshRate = 50
        var m75 = mode; m75.refreshRate = 75
        XCTAssertEqual(DisplayMode.best(for: mode, among: [m50, mode, m75]), 1)
        var want = mode; want.refreshRate = 70
        XCTAssertEqual(DisplayMode.best(for: want, among: [m50, m75]), 1)
    }

    func testStoreRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("p.json")
        let store = ProfileStore(url: url)
        let profile = Profile(placements: [place("a", 1), place("b", 2)])
        try store.save(profile)
        XCTAssertEqual(store.profile(for: ["b", "a"])?.placements, profile.placements)
        try store.remove(id: profile.id)
        XCTAssertNil(store.profile(for: ["a", "b"]))
    }
}
