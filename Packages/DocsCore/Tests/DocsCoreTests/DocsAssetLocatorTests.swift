import DocsCore
import Foundation
import XCTest

final class DocsAssetLocatorTests: XCTestCase {
    func testLocateInstalledAssetFromFixture() throws {
        let root = try makeFixtureRoot(xcodeVersion: "27.0")
        let locator = DocsAssetLocator()
        let descriptor = try locator.locateInstalledAsset(rootURL: root)
        XCTAssertEqual(descriptor.xcodeVersion, "27.0")
        XCTAssertEqual(descriptor.documentationRelease, "950001")
    }

    func testRejectsIncompatibleVersion() throws {
        let root = try makeFixtureRoot(xcodeVersion: "26.0")
        let locator = DocsAssetLocator()
        XCTAssertThrowsError(try locator.locateInstalledAsset(rootURL: root))
    }

    private func makeFixtureRoot(xcodeVersion: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let asset = root.appendingPathComponent("fixture.asset", isDirectory: true)
        let assetData = asset.appendingPathComponent("AssetData", isDirectory: true)
        let db = assetData.appendingPathComponent("documentation-db", isDirectory: true)
        let cache = assetData.appendingPathComponent("documentation-cache", isDirectory: true)
        let fs = cache.appendingPathComponent("fs", isDirectory: true)

        try FileManager.default.createDirectory(at: db, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fs, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: db.appendingPathComponent("index.sql").path, contents: Data())
        FileManager.default.createFile(atPath: cache.appendingPathComponent("cache.db").path, contents: Data())

        let plist: [String: Any] = [
            "MobileAssetProperties": [
                "XcodeVersion": xcodeVersion,
                "DocumentationRelease": "950001",
                "OSVersion": "27.0"
            ]
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try FileManager.default.createDirectory(at: asset, withIntermediateDirectories: true)
        try plistData.write(to: asset.appendingPathComponent("Info.plist"))
        return root
    }
}
