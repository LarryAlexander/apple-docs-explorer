import Foundation
import SQLite3

public protocol DocsProviding: Sendable {
    func assetDescriptor() throws -> DocsAssetDescriptor
    func searchDocuments(query: SearchQuery) throws -> [DocEntry]
    func frameworks(limit: Int) throws -> [String]
    func frameworkOverviewEntries(limit: Int) throws -> [DocEntry]
    func browseEntries(category: BrowseCategory, limit: Int) throws -> [DocEntry]
    func entries(inFramework framework: String, limit: Int) throws -> [DocEntry]
    func entry(assetID: String) throws -> DocEntry?
    func relatedEntries(assetID: String, limit: Int) throws -> [DocEntry]
}

public final class DocsStore: DocsProviding, @unchecked Sendable {
    private static let frameworkLookupExpression = "COALESCE(a.framework, json_extract(CAST(d.document AS TEXT), '$.modules[0]'), json_extract(CAST(d.document AS TEXT), '$.fileName'), '')"
    private static let normalizedFrameworkLookupExpression = "lower(replace(replace(replace(replace(replace(replace(\(frameworkLookupExpression), ' ', ''), '-', ''), '&', ''), '/', ''), '.', ''), '_', ''))"

    private let locator: DocsAssetLocator
    private let descriptor: DocsAssetDescriptor
    private let database: SQLiteDatabase
    private let decoder = JSONDecoder()

    public init(locator: DocsAssetLocator = DocsAssetLocator()) throws {
        self.locator = locator
        let descriptor = try locator.locateInstalledAsset()
        self.descriptor = descriptor
        self.database = try SQLiteDatabase(path: descriptor.databaseURL.path)
    }

    public func assetDescriptor() throws -> DocsAssetDescriptor {
        descriptor
    }

    public func searchDocuments(query: SearchQuery) throws -> [DocEntry] {
        let normalized = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return []
        }

        var sql = """
        SELECT d.asset_id, CAST(d.document AS TEXT), a.content
        FROM documents d
        JOIN attributes a ON a.asset_id = d.asset_id
        WHERE a.content IS NOT NULL
          AND a.content != ''
          AND (
            lower(d.asset_id) LIKE ?1
            OR lower(CAST(d.document AS TEXT)) LIKE ?1
            OR lower(COALESCE(a.title, '')) LIKE ?1
            OR lower(COALESCE(a.framework, '')) LIKE ?1
            OR lower(COALESCE(a.type, '')) LIKE ?1
            OR lower(a.content) LIKE ?1
          )
        """

        if query.framework?.isEmpty == false {
            sql += " AND \(Self.normalizedFrameworkLookupExpression) = ?2"
        }

        sql += """
         ORDER BY
            CASE
                WHEN lower(COALESCE(a.title, json_extract(CAST(d.document AS TEXT), '$.fileName'), '')) = ?\(query.framework?.isEmpty == false ? 3 : 2) THEN 0
                WHEN lower(d.asset_id) LIKE ?\(query.framework?.isEmpty == false ? 4 : 3) THEN 1
                WHEN lower(COALESCE(a.title, '')) LIKE ?1 THEN 2
                WHEN lower(COALESCE(a.type, '')) LIKE ?1 THEN 3
                ELSE 4
            END,
            length(COALESCE(a.title, '')),
            d.asset_id
         LIMIT ?\(query.framework?.isEmpty == false ? 5 : 4)
        """
        let statement = try database.prepare(sql)
        defer { sqlite3_finalize(statement) }

        let pattern = "%\(normalized.lowercased())%"
        let exactTitle = normalized.lowercased()
        let assetSuffix = "%/\(normalized.lowercased())"
        try bindText(pattern, index: 1, to: statement)
        if let framework = query.framework, !framework.isEmpty {
            try bindText(Self.normalizedFrameworkKey(framework), index: 2, to: statement)
            try bindText(exactTitle, index: 3, to: statement)
            try bindText(assetSuffix, index: 4, to: statement)
            try bindInt(max(query.limit * 40, 400), index: 5, to: statement)
        } else {
            try bindText(exactTitle, index: 2, to: statement)
            try bindText(assetSuffix, index: 3, to: statement)
            try bindInt(max(query.limit * 40, 400), index: 4, to: statement)
        }

        return try readEntries(from: statement)
    }

    public func frameworks(limit: Int = 200) throws -> [String] {
        let sql = """
        SELECT COALESCE(json_extract(CAST(d.document AS TEXT), '$.modules[0]'), MAX(a.framework), json_extract(CAST(d.document AS TEXT), '$.fileName'))
        FROM documents d
        JOIN attributes a ON a.asset_id = d.asset_id
        WHERE a.content IS NOT NULL
          AND a.content != ''
          AND json_extract(CAST(d.document AS TEXT), '$.roleHeading') = 'Framework'
          AND json_extract(CAST(d.document AS TEXT), '$.symbol.kind') = 'Framework'
          AND d.asset_id NOT LIKE '%#%'
        GROUP BY d.asset_id
        ORDER BY COALESCE(json_extract(CAST(d.document AS TEXT), '$.modules[0]'), MAX(a.framework), json_extract(CAST(d.document AS TEXT), '$.fileName')) COLLATE NOCASE
        LIMIT ?1
        """
        let statement = try database.prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bindInt(limit, index: 1, to: statement)

        var result: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let raw = sqlite3_column_text(statement, 0) {
                result.append(String(cString: raw))
            }
        }
        return result
    }

    public func frameworkOverviewEntries(limit: Int = 200) throws -> [DocEntry] {
        let sql = """
        SELECT d.asset_id, CAST(d.document AS TEXT), MAX(a.content)
        FROM documents d
        JOIN attributes a ON a.asset_id = d.asset_id
        WHERE a.content IS NOT NULL
          AND a.content != ''
          AND json_extract(CAST(d.document AS TEXT), '$.roleHeading') = 'Framework'
          AND json_extract(CAST(d.document AS TEXT), '$.symbol.kind') = 'Framework'
          AND d.asset_id NOT LIKE '%#%'
        GROUP BY d.asset_id
        ORDER BY COALESCE(json_extract(CAST(d.document AS TEXT), '$.modules[0]'), MAX(a.framework), json_extract(CAST(d.document AS TEXT), '$.fileName')) COLLATE NOCASE
        LIMIT ?1
        """
        let statement = try database.prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bindInt(limit, index: 1, to: statement)
        return try readEntries(from: statement)
    }

    public func browseEntries(category: BrowseCategory, limit: Int = 500) throws -> [DocEntry] {
        if category == .frameworks {
            return try frameworkOverviewEntries(limit: limit)
        }

        let predicate: String
        switch category {
        case .all:
            predicate = "1 = 1"
        case .topics:
            predicate = "json_extract(CAST(d.document AS TEXT), '$.role') = 'collectionGroup'"
        case .articles:
            predicate = "json_extract(CAST(d.document AS TEXT), '$.role') = 'article'"
        case .tutorials:
            predicate = "json_extract(CAST(d.document AS TEXT), '$.role') = 'tutorial'"
        case .samples:
            predicate = "json_extract(CAST(d.document AS TEXT), '$.role') = 'sampleCode'"
        case .symbols:
            predicate = """
            json_extract(CAST(d.document AS TEXT), '$.role') = 'symbol'
              AND COALESCE(json_extract(CAST(d.document AS TEXT), '$.symbol.kind'), '') != 'Framework'
            """
        case .other:
            predicate = """
            COALESCE(json_extract(CAST(d.document AS TEXT), '$.role'), 'unknown') NOT IN ('collectionGroup', 'article', 'tutorial', 'sampleCode', 'symbol')
            """
        case .frameworks:
            predicate = "1 = 0"
        }

        let sql = """
        SELECT d.asset_id, CAST(d.document AS TEXT), MAX(a.content)
        FROM documents d
        JOIN attributes a ON a.asset_id = d.asset_id
        WHERE a.content IS NOT NULL
          AND a.content != ''
          AND \(predicate)
        GROUP BY d.asset_id
        ORDER BY
          COALESCE(json_extract(CAST(d.document AS TEXT), '$.modules[0]'), MAX(a.framework), '') COLLATE NOCASE,
          CASE json_extract(CAST(d.document AS TEXT), '$.role')
            WHEN 'collectionGroup' THEN 0
            WHEN 'article' THEN 1
            WHEN 'tutorial' THEN 2
            WHEN 'sampleCode' THEN 3
            WHEN 'symbol' THEN 4
            ELSE 5
          END,
          COALESCE(json_extract(CAST(d.document AS TEXT), '$.title'), json_extract(CAST(d.document AS TEXT), '$.fileName'), d.asset_id) COLLATE NOCASE
        LIMIT ?1
        """
        let statement = try database.prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bindInt(limit, index: 1, to: statement)
        return try readEntries(from: statement)
    }

    public func entries(inFramework framework: String, limit: Int = 200) throws -> [DocEntry] {
        let sql = """
        SELECT d.asset_id, CAST(d.document AS TEXT), a.content
        FROM documents d
        JOIN attributes a ON a.asset_id = d.asset_id
        WHERE a.content IS NOT NULL
          AND a.content != ''
          AND \(Self.normalizedFrameworkLookupExpression) = ?1
        ORDER BY d.asset_id
        LIMIT ?2
        """
        let statement = try database.prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bindText(Self.normalizedFrameworkKey(framework), index: 1, to: statement)
        try bindInt(limit, index: 2, to: statement)
        return try readEntries(from: statement)
    }

    public func entry(assetID: String) throws -> DocEntry? {
        let sql = """
        SELECT d.asset_id, CAST(d.document AS TEXT), a.content
        FROM documents d
        LEFT JOIN attributes a ON a.asset_id = d.asset_id AND a.content IS NOT NULL AND a.content != ''
        WHERE d.asset_id = ?1
        LIMIT 1
        """
        let statement = try database.prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bindText(assetID, index: 1, to: statement)
        return try readEntries(from: statement).first
    }

    public func relatedEntries(assetID: String, limit: Int = 10) throws -> [DocEntry] {
        guard let reference = try entry(assetID: assetID) else {
            return []
        }

        let sql = """
        SELECT d.asset_id, CAST(d.document AS TEXT), a.content
        FROM documents d
        JOIN attributes a ON a.asset_id = d.asset_id
        WHERE d.asset_id != ?1
          AND a.content IS NOT NULL
          AND a.content != ''
          AND \(Self.normalizedFrameworkLookupExpression) = ?2
          AND d.asset_id LIKE ?3
        LIMIT ?4
        """

        let statement = try database.prepare(sql)
        defer { sqlite3_finalize(statement) }

        let prefix = reference.assetID.split(separator: "#").first.map(String.init) ?? reference.assetID
        try bindText(assetID, index: 1, to: statement)
        try bindText(Self.normalizedFrameworkKey(reference.framework), index: 2, to: statement)
        try bindText("\(prefix)%", index: 3, to: statement)
        try bindInt(limit, index: 4, to: statement)

        return try readEntries(from: statement)
    }

    private static func normalizedFrameworkKey(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private func readEntries(from statement: OpaquePointer?) throws -> [DocEntry] {
        var entries: [DocEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let assetIDRaw = sqlite3_column_text(statement, 0),
                let documentRaw = sqlite3_column_text(statement, 1)
            else {
                continue
            }

            let assetID = String(cString: assetIDRaw)
            let documentString = String(cString: documentRaw)
            guard let documentData = documentString.data(using: String.Encoding.utf8) else {
                throw DocsError.invalidDocument(assetID)
            }

            let metadata = try decoder.decode(DocMetadata.self, from: documentData)
            let content: String?
            if let contentRaw = sqlite3_column_text(statement, 2) {
                let raw = String(cString: contentRaw).trimmingCharacters(in: .whitespacesAndNewlines)
                content = raw.isEmpty ? nil : raw
            } else {
                content = nil
            }
            let entry = DocEntry(
                assetID: assetID,
                metadata: metadata,
                rawDocumentJSON: documentString,
                content: content
            )
            entries.append(entry)
        }

        return entries
    }
}
