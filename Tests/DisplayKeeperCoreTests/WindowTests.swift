import XCTest
@testable import DisplayKeeperCore

final class WindowTests: XCTestCase {
    func saved(_ app: String, _ title: String, _ index: Int = 0, id: UInt32? = nil, pid: Int32? = nil) -> SavedWindow {
        SavedWindow(bundleID: app, appName: app, title: title, index: index, displayKey: "d",
                    x: 10, y: 20, width: 800, height: 600, windowID: id, pid: pid)
    }

    func live(_ app: String, _ title: String, _ index: Int = 0, id: UInt32? = nil, pid: Int32 = 1) -> LiveWindow {
        LiveWindow(bundleID: app, title: title, index: index, windowID: id, pid: pid, x: 0, y: 0, width: 1, height: 1)
    }

    func testSameWindowWinsEvenIfTitleChanged() {
        let m = WindowMatcher.match(saved: [saved("a", "old", id: 7, pid: 1)],
                                    live: [live("a", "old", id: 8), live("a", "new", id: 7)])
        XCTAssertEqual(m.first?.live.windowID, 7)
    }

    func testReusedWindowIDFromOtherProcessIsIgnored() {
        let m = WindowMatcher.match(saved: [saved("a", "doc", id: 7, pid: 1)],
                                    live: [live("a", "other", id: 7, pid: 2), live("a", "doc", 1, id: 9, pid: 2)])
        XCTAssertEqual(m.first?.live.title, "doc")
    }

    func testFallsBackToTitleThenIndex() {
        let m = WindowMatcher.match(
            saved: [saved("a", "", 1), saved("a", "Inbox", 0)],
            live: [live("a", "Inbox", 0), live("a", "", 1)])
        XCTAssertEqual(m.map { "\($0.saved.index)->\($0.live.index)" }.sorted(), ["0->0", "1->1"])
    }

    func testEachLiveWindowUsedOnce() {
        let m = WindowMatcher.match(saved: [saved("a", "x"), saved("a", "x")], live: [live("a", "x")])
        XCTAssertEqual(m.count, 1)
    }

    func testOtherAppsDoNotMatch() {
        XCTAssertTrue(WindowMatcher.match(saved: [saved("a", "x")], live: [live("b", "x")]).isEmpty)
    }

    func testTargetIsRelativeToDisplayOrigin() {
        let t = WindowMatcher.target(for: saved("a", "x"), origins: ["d": (x: -2261, y: -1890)])
        XCTAssertEqual(t?.x, -2251)
        XCTAssertEqual(t?.y, -1870)
        XCTAssertNil(WindowMatcher.target(for: saved("a", "x"), origins: [:]))
    }

    func testOldProfilesWithoutWindowsStillDecode() throws {
        let json = #"{"placements":[],"savedAt":"2026-10-17T15:41:55Z"}"#.data(using: .utf8)!
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try d.decode(Profile.self, from: json).windows, [])
    }
}
