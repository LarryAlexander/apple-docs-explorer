import DocsCore
import Foundation
import XCTest

final class SearchEngineTests: XCTestCase {
    func testExactTitleRanksAboveBroadContentMatch() throws {
        let store = StubDocsStore(entries: [
            makeEntry(assetID: "/documentation/SwiftUI/Text", title: "Text", framework: "SwiftUI", roleHeading: "Structure", role: "symbol", content: "A view that displays one or more lines of read-only text."),
            makeEntry(assetID: "/documentation/HIG/accessibility", title: "Accessibility", framework: "Human-Interface-Guidelines", roleHeading: "Article", role: "article", content: "This broad article mentions text many times.")
        ])

        let engine = SearchEngine(store: store)
        let response = try engine.search(SearchQuery(text: "Text", limit: 10))

        XCTAssertEqual(response.results.first?.assetID, "/documentation/SwiftUI/Text")
    }

    func testFrameworkFilterRestrictsResults() throws {
        let store = StubDocsStore(entries: [
            makeEntry(assetID: "/documentation/SwiftUI/Text", title: "Text", framework: "SwiftUI", roleHeading: "Structure", role: "symbol", content: "SwiftUI text."),
            makeEntry(assetID: "/documentation/PDFKit/Text", title: "Text", framework: "PDFKit", roleHeading: "Type Property", role: "symbol", content: "PDF text.")
        ])

        let engine = SearchEngine(store: store)
        let response = try engine.search(SearchQuery(text: "Text", framework: "SwiftUI", limit: 10))

        XCTAssertEqual(response.results.count, 1)
        XCTAssertEqual(response.results.first?.framework, "SwiftUI")
    }

    func testBrowseFrameworkGroupsOverviewBeforeSymbols() throws {
        let store = StubDocsStore(entries: [
            makeEntry(assetID: "/documentation/SwiftUI/Text", title: "Text", framework: "SwiftUI", roleHeading: "Structure", role: "symbol", content: "A text view."),
            makeEntry(assetID: "/documentation/SwiftUI/controls", title: "Controls", framework: "SwiftUI", roleHeading: nil, role: "collectionGroup", content: "Controls and inputs."),
            makeEntry(assetID: "/documentation/SwiftUI", title: "SwiftUI", framework: "SwiftUI", roleHeading: "Framework", role: "symbol", content: "Build user interfaces."),
            makeEntry(assetID: "/documentation/SwiftUI/accessibility", title: "Accessibility", framework: "SwiftUI", roleHeading: "Article", role: "article", content: "Make SwiftUI apps accessible.")
        ])

        let engine = SearchEngine(store: store)
        let sections = try engine.browseFramework("SwiftUI", filter: BrowseFilter(limit: 10))

        XCTAssertEqual(sections.map(\.title), ["Framework Overview", "Topics", "Articles", "Symbols"])
        XCTAssertEqual(sections.first?.results.first?.assetID, "/documentation/SwiftUI")
    }

    func testBrowseFilterTextAndCategoryRestrictSections() throws {
        let store = StubDocsStore(entries: [
            makeEntry(assetID: "/documentation/SwiftUI", title: "SwiftUI", framework: "SwiftUI", roleHeading: "Framework", role: "symbol", content: "Build user interfaces."),
            makeEntry(assetID: "/documentation/SwiftUI/accessibility", title: "Accessibility", framework: "SwiftUI", roleHeading: "Article", role: "article", content: "Make SwiftUI apps accessible."),
            makeEntry(assetID: "/documentation/SwiftUI/Text", title: "Text", framework: "SwiftUI", roleHeading: "Structure", role: "symbol", content: "A text view.")
        ])

        let engine = SearchEngine(store: store)
        let sections = try engine.browseFramework("SwiftUI", filter: BrowseFilter(text: "accessibility", category: .articles, limit: 10))

        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections.first?.title, "Articles")
        XCTAssertEqual(sections.first?.results.map(\.assetID), ["/documentation/SwiftUI/accessibility"])
    }

    func testAllBrowseCategoryReturnsNonFrameworkEntriesGroupedByFramework() throws {
        let store = StubDocsStore(entries: [
            makeEntry(assetID: "/documentation/CloudKit", title: "CloudKit", framework: "CloudKit", roleHeading: "Framework", role: "symbol", content: "Store app data in iCloud."),
            makeEntry(assetID: "/documentation/CloudKit/sharing", title: "Sharing CloudKit data", framework: "CloudKit", roleHeading: nil, role: "article", content: "Share records with other users."),
            makeEntry(assetID: "/documentation/ActivityKit/live-activities", title: "Displaying live data", framework: "ActivityKit", roleHeading: nil, role: "article", content: "Present Live Activities.")
        ])

        let engine = SearchEngine(store: store)
        let sections = try engine.browseFrameworks(filter: BrowseFilter(category: .articles, limit: 10))

        XCTAssertEqual(sections.map(\.title), ["ActivityKit", "CloudKit"])
        XCTAssertEqual(sections.flatMap(\.results).map(\.docType), ["article", "article"])
    }

    func testMatchingFrameworkNormalizesKitNames() throws {
        let store = StubDocsStore(entries: [
            makeEntry(assetID: "/documentation/CloudKit", title: "CloudKit", framework: "CloudKit", roleHeading: "Framework", role: "symbol", content: "Store app data in iCloud."),
            makeEntry(assetID: "/documentation/ActivityKit", title: "ActivityKit", framework: "ActivityKit", roleHeading: "Framework", role: "symbol", content: "Share live updates.")
        ])

        let engine = SearchEngine(store: store)

        XCTAssertEqual(try engine.matchingFramework(named: "cloud kit"), "CloudKit")
        XCTAssertEqual(try engine.matchingFramework(named: "Activity Kit"), "ActivityKit")
    }

    func testBrowseFrameworkMatchesDisplayNameToCompactAssetIdentifier() throws {
        let store = StubDocsStore(entries: [
            makeEntry(assetID: "/documentation/AccessoryNotifications", title: "Accessory Notifications", framework: "AccessoryNotifications", roleHeading: "Framework", role: "symbol", content: "Schedule accessory notifications."),
            makeEntry(assetID: "/documentation/AccessoryNotifications/authorization", title: "Requesting Authorization", framework: "AccessoryNotifications", roleHeading: "Article", role: "article", content: "Ask users for permission.")
        ])

        let engine = SearchEngine(store: store)
        let sections = try engine.browseFramework("Accessory Notifications", filter: BrowseFilter(limit: 10))

        XCTAssertEqual(sections.flatMap(\.results).map(\.assetID), [
            "/documentation/AccessoryNotifications",
            "/documentation/AccessoryNotifications/authorization"
        ])
    }

    private func makeEntry(
        assetID: String,
        title: String,
        framework: String,
        roleHeading: String?,
        role: String,
        content: String
    ) -> DocEntry {
        let metadata = DocMetadata(
            uri: assetID,
            title: title,
            fileName: title,
            kind: role,
            role: role,
            roleHeading: roleHeading,
            modules: [framework],
            platforms: nil,
            symbol: DocSymbolMetadata(kind: roleHeading, preciseIdentifier: assetID),
            externalID: assetID
        )

        return DocEntry(
            assetID: assetID,
            metadata: metadata,
            rawDocumentJSON: "{}",
            content: content
        )
    }
}

private struct StubDocsStore: DocsProviding {
    let entries: [DocEntry]

    func assetDescriptor() throws -> DocsAssetDescriptor {
        DocsAssetDescriptor(
            rootURL: URL(fileURLWithPath: "/tmp", isDirectory: true),
            assetURL: URL(fileURLWithPath: "/tmp/fixture.asset", isDirectory: true),
            infoPlistURL: URL(fileURLWithPath: "/tmp/Info.plist"),
            databaseURL: URL(fileURLWithPath: "/tmp/index.sql"),
            cacheDatabaseURL: URL(fileURLWithPath: "/tmp/cache.db"),
            cacheFileStoreURL: URL(fileURLWithPath: "/tmp/fs", isDirectory: true),
            documentationRelease: "950001",
            xcodeVersion: "27.0",
            osVersion: "27.0"
        )
    }

    func searchDocuments(query: SearchQuery) throws -> [DocEntry] {
        entries.filter { entry in
            let haystack = [entry.assetID, entry.title, entry.framework, entry.docType, entry.content ?? ""]
                .joined(separator: " ")
                .lowercased()
            let matchesQuery = haystack.contains(query.text.lowercased())
            let matchesFramework = query.framework.map { normalizedFrameworkKey(entry.framework) == normalizedFrameworkKey($0) } ?? true
            return matchesQuery && matchesFramework
        }
    }

    func frameworks(limit: Int) throws -> [String] {
        Array(Set(entries.map(\.framework))).sorted().prefix(limit).map { $0 }
    }

    func frameworkOverviewEntries(limit: Int) throws -> [DocEntry] {
        entries.filter { $0.docType == "Framework" }.prefix(limit).map { $0 }
    }

    func browseEntries(category: BrowseCategory, limit: Int) throws -> [DocEntry] {
        entries.filter { category.matches($0) }.prefix(limit).map { $0 }
    }

    func entries(inFramework framework: String, limit: Int) throws -> [DocEntry] {
        entries.filter { normalizedFrameworkKey($0.framework) == normalizedFrameworkKey(framework) }.prefix(limit).map { $0 }
    }

    func entry(assetID: String) throws -> DocEntry? {
        entries.first { $0.assetID == assetID }
    }

    func relatedEntries(assetID: String, limit: Int) throws -> [DocEntry] {
        guard let base = entries.first(where: { $0.assetID == assetID }) else { return [] }
        return entries.filter { $0.assetID != assetID && $0.framework == base.framework }.prefix(limit).map { $0 }
    }

    private func normalizedFrameworkKey(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
