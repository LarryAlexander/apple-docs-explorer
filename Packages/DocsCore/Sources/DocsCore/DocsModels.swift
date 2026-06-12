import Foundation

public struct DocsAssetDescriptor: Sendable, Equatable {
    public let rootURL: URL
    public let assetURL: URL
    public let infoPlistURL: URL
    public let databaseURL: URL
    public let cacheDatabaseURL: URL
    public let cacheFileStoreURL: URL
    public let documentationRelease: String
    public let xcodeVersion: String
    public let osVersion: String

    public init(
        rootURL: URL,
        assetURL: URL,
        infoPlistURL: URL,
        databaseURL: URL,
        cacheDatabaseURL: URL,
        cacheFileStoreURL: URL,
        documentationRelease: String,
        xcodeVersion: String,
        osVersion: String
    ) {
        self.rootURL = rootURL
        self.assetURL = assetURL
        self.infoPlistURL = infoPlistURL
        self.databaseURL = databaseURL
        self.cacheDatabaseURL = cacheDatabaseURL
        self.cacheFileStoreURL = cacheFileStoreURL
        self.documentationRelease = documentationRelease
        self.xcodeVersion = xcodeVersion
        self.osVersion = osVersion
    }
}

public struct DocPlatform: Codable, Sendable, Equatable {
    public let platform: String?
    public let introduced: Double?
    public let deprecated: Bool?

    public init(platform: String?, introduced: Double?, deprecated: Bool?) {
        self.platform = platform
        self.introduced = introduced
        self.deprecated = deprecated
    }
}

public struct DocSymbolMetadata: Codable, Sendable, Equatable {
    public let kind: String?
    public let preciseIdentifier: String?

    public init(kind: String?, preciseIdentifier: String?) {
        self.kind = kind
        self.preciseIdentifier = preciseIdentifier
    }
}

public struct DocMetadata: Codable, Sendable, Equatable {
    public let uri: String?
    public let title: String?
    public let fileName: String?
    public let kind: String?
    public let role: String?
    public let roleHeading: String?
    public let modules: [String]?
    public let platforms: [DocPlatform]?
    public let symbol: DocSymbolMetadata?
    public let externalID: String?

    enum CodingKeys: String, CodingKey {
        case uri
        case title
        case fileName
        case kind
        case role
        case roleHeading
        case modules
        case platforms
        case symbol
        case externalID = "external_id"
    }

    public init(
        uri: String?,
        title: String?,
        fileName: String?,
        kind: String?,
        role: String?,
        roleHeading: String?,
        modules: [String]?,
        platforms: [DocPlatform]?,
        symbol: DocSymbolMetadata?,
        externalID: String?
    ) {
        self.uri = uri
        self.title = title
        self.fileName = fileName
        self.kind = kind
        self.role = role
        self.roleHeading = roleHeading
        self.modules = modules
        self.platforms = platforms
        self.symbol = symbol
        self.externalID = externalID
    }
}

public struct DocEntry: Sendable, Equatable, Identifiable {
    public let assetID: String
    public let metadata: DocMetadata
    public let rawDocumentJSON: String
    public let content: String?

    public init(assetID: String, metadata: DocMetadata, rawDocumentJSON: String, content: String?) {
        self.assetID = assetID
        self.metadata = metadata
        self.rawDocumentJSON = rawDocumentJSON
        self.content = content
    }

    public var id: String { assetID }
    public var title: String {
        metadata.title ?? metadata.fileName ?? assetID.split(separator: "/").last.map(String.init) ?? assetID
    }

    public var framework: String {
        metadata.modules?.first ?? inferredFramework
    }

    public var docType: String {
        metadata.roleHeading ?? metadata.role ?? metadata.kind ?? "Documentation"
    }

    public var inferredFramework: String {
        let components = assetID.split(separator: "/")
        if components.count >= 3 {
            return String(components[1])
        }
        return "Apple"
    }

    public var snippetSource: String {
        if let content, !content.isEmpty {
            return content
        }

        let segments = [
            metadata.roleHeading,
            metadata.kind,
            metadata.title,
            metadata.fileName,
            metadata.symbol?.preciseIdentifier
        ].compactMap { $0 }

        return segments.joined(separator: " • ")
    }
}

public struct LocalSummaryGenerator: Sendable {
    public init() {}

    public func summary(for entry: DocEntry, maxSentences: Int = 3) -> String {
        let source = entry.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? entry.snippetSource
        guard !source.isEmpty else { return "" }

        let normalized = source.replacingOccurrences(of: "\n", with: " ")
        let segments = normalized
            .split(separator: ".")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let prefix = segments.prefix(maxSentences).joined(separator: ". ")
        if prefix.isEmpty {
            return String(normalized.prefix(320))
        }

        return prefix.hasSuffix(".") ? prefix : "\(prefix)."
    }
}

public struct SearchResult: Sendable, Equatable, Identifiable {
    public let assetID: String
    public let title: String
    public let framework: String
    public let docType: String
    public let snippet: String
    public let score: Int

    public var id: String { assetID }
}

public enum BrowseCategory: String, CaseIterable, Sendable, Equatable, Identifiable {
    case all
    case frameworks
    case topics
    case articles
    case tutorials
    case samples
    case symbols
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .all:
            return "All"
        case .frameworks:
            return "Frameworks"
        case .topics:
            return "Topics"
        case .articles:
            return "Articles"
        case .tutorials:
            return "Tutorials"
        case .samples:
            return "Samples"
        case .symbols:
            return "Symbols"
        case .other:
            return "Other"
        }
    }

    public func matches(_ entry: DocEntry) -> Bool {
        self == .all || Self.category(for: entry) == self
    }

    public static func category(for entry: DocEntry) -> BrowseCategory {
        let role = entry.metadata.role?.lowercased() ?? ""
        let docType = entry.docType.lowercased()
        let symbolKind = entry.metadata.symbol?.kind?.lowercased() ?? ""

        if docType == "framework" || symbolKind == "framework" {
            return .frameworks
        }

        switch role {
        case "collectiongroup":
            return .topics
        case "article":
            return .articles
        case "tutorial":
            return .tutorials
        case "samplecode":
            return .samples
        case "symbol":
            return .symbols
        case "unknown":
            return .other
        default:
            break
        }

        if docType == "article" {
            return .articles
        }

        return .other
    }
}

public struct BrowseFilter: Sendable, Equatable {
    public let text: String
    public let category: BrowseCategory
    public let limit: Int

    public init(text: String = "", category: BrowseCategory = .all, limit: Int = 200) {
        self.text = text
        self.category = category
        self.limit = limit
    }
}

public struct BrowseSection: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let results: [SearchResult]

    public init(id: String, title: String, results: [SearchResult]) {
        self.id = id
        self.title = title
        self.results = results
    }
}

public struct SearchQuery: Sendable, Equatable {
    public let text: String
    public let framework: String?
    public let limit: Int

    public init(text: String, framework: String? = nil, limit: Int = 20) {
        self.text = text
        self.framework = framework
        self.limit = limit
    }
}

public enum DocsError: Error, LocalizedError, Sendable {
    case assetNotFound(URL)
    case incompatibleAssetVersion(String)
    case missingRequiredFile(URL)
    case sqliteError(String)
    case invalidDocument(String)
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case let .assetNotFound(url):
            return "No Apple documentation asset was found at \(url.path)."
        case let .incompatibleAssetVersion(version):
            return "The installed documentation asset is incompatible: \(version)."
        case let .missingRequiredFile(url):
            return "A required asset file is missing: \(url.path)."
        case let .sqliteError(message):
            return "SQLite error: \(message)"
        case let .invalidDocument(identifier):
            return "The document payload could not be decoded for \(identifier)."
        case let .unsupported(message):
            return message
        }
    }
}

public struct SearchResponse: Sendable, Equatable {
    public let query: SearchQuery
    public let results: [SearchResult]
}
