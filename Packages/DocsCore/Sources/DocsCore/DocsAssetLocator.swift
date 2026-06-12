import Foundation

public struct DocsAssetLocator: Sendable {
    public static let defaultRootURL = URL(fileURLWithPath: "/System/Library/AssetsV2/com_apple_MobileAsset_AppleDeveloperDocumentation", isDirectory: true)
    public static let assetRootEnvironmentKey = "APPLE_DOCS_ASSET_ROOT"

    public init() {}

    public func locateInstalledAsset(rootURL: URL? = nil) throws -> DocsAssetDescriptor {
        let rootURL = rootURL ?? Self.environmentRootURL ?? Self.defaultRootURL
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: rootURL.path) else {
            throw DocsError.assetNotFound(rootURL)
        }

        let assetDirectory = try latestAssetDirectory(in: rootURL)
        let infoPlistURL = assetDirectory.appendingPathComponent("Info.plist")
        let assetDataURL = assetDirectory.appendingPathComponent("AssetData", isDirectory: true)
        let databaseURL = assetDataURL.appendingPathComponent("documentation-db/index.sql")
        let cacheDatabaseURL = assetDataURL.appendingPathComponent("documentation-cache/cache.db")
        let cacheFileStoreURL = assetDataURL.appendingPathComponent("documentation-cache/fs", isDirectory: true)

        for requiredURL in [infoPlistURL, databaseURL, cacheDatabaseURL, cacheFileStoreURL] {
            guard fileManager.fileExists(atPath: requiredURL.path) else {
                throw DocsError.missingRequiredFile(requiredURL)
            }
        }

        let plist = try readInfoPlist(at: infoPlistURL)
        let properties = plist["MobileAssetProperties"] as? [String: Any] ?? [:]
        let xcodeVersion = String(describing: properties["XcodeVersion"] ?? "")
        let documentationRelease = String(describing: properties["DocumentationRelease"] ?? "")
        let osVersion = String(describing: properties["OSVersion"] ?? "")

        guard xcodeVersion.hasPrefix("27.") || xcodeVersion == "27" else {
            throw DocsError.incompatibleAssetVersion(xcodeVersion)
        }

        return DocsAssetDescriptor(
            rootURL: rootURL,
            assetURL: assetDirectory,
            infoPlistURL: infoPlistURL,
            databaseURL: databaseURL,
            cacheDatabaseURL: cacheDatabaseURL,
            cacheFileStoreURL: cacheFileStoreURL,
            documentationRelease: documentationRelease,
            xcodeVersion: xcodeVersion,
            osVersion: osVersion
        )
    }

    private static var environmentRootURL: URL? {
        guard let path = ProcessInfo.processInfo.environment[assetRootEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty
        else {
            return nil
        }

        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func latestAssetDirectory(in rootURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        let assetDirectories = contents.filter { $0.pathExtension == "asset" }
        guard let latest = try assetDirectories.max(by: { lhs, rhs in
            let lhsValues = try lhs.resourceValues(forKeys: [.contentModificationDateKey])
            let rhsValues = try rhs.resourceValues(forKeys: [.contentModificationDateKey])
            return (lhsValues.contentModificationDate ?? .distantPast) < (rhsValues.contentModificationDate ?? .distantPast)
        }) else {
            throw DocsError.assetNotFound(rootURL)
        }

        return latest
    }

    private func readInfoPlist(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let dictionary = plist as? [String: Any] else {
            throw DocsError.unsupported("The asset Info.plist is not a dictionary.")
        }
        return dictionary
    }
}
