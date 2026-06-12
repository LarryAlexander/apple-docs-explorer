import AppKit
import DocsCore
import Foundation
import Observation

@Observable
@MainActor
final class AppModel {
    var searchText = ""
    var browseFilterText = ""
    var frameworkFilterText = ""
    var selectedBrowseCategory: BrowseCategory = .all
    var selectedFramework: String?
    var frameworks: [String] = []
    var resultSections: [BrowseSection] = []
    var selectedEntry: DocEntry?
    var relatedResults: [SearchResult] = []
    var assetDescriptor: DocsAssetDescriptor?
    var errorMessage: String?
    var isLoading = false
    var showSummary = false
    var localSummary = ""
    var resultsTitle = "Search Results"
    var isBrowseMode = true

    private var engine: SearchEngine?
    private let summaryGenerator = LocalSummaryGenerator()

    var searchResults: [SearchResult] {
        resultSections.flatMap(\.results)
    }

    var resultCount: Int {
        searchResults.count
    }

    var filteredFrameworks: [String] {
        let filter = frameworkFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !filter.isEmpty else {
            return frameworks
        }

        let normalizedFilter = normalizedFrameworkKey(filter)
        return frameworks.filter { framework in
            framework.localizedCaseInsensitiveContains(filter)
                || normalizedFrameworkKey(framework).contains(normalizedFilter)
        }
    }

    var hasActiveBrowseFilters: Bool {
        !browseFilterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedBrowseCategory != .all
    }

    func bootstrap() async {
        guard engine == nil else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let store = try DocsStore()
            let engine = SearchEngine(store: store)
            self.engine = engine
            assetDescriptor = try engine.assetDescriptor()
            frameworks = try engine.frameworks(limit: 500)
            try await browseAllFrameworks(resetCategory: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func performSearch() async throws {
        guard let engine else { return }
        isLoading = true
        defer { isLoading = false }

        let response = try engine.search(SearchQuery(text: searchText, framework: selectedFramework, limit: 40))
        resultSections = [
            BrowseSection(id: "search", title: "Results", results: response.results)
        ]
        resultsTitle = selectedFramework.map { "Search in \($0)" } ?? "Search Results"
        isBrowseMode = false
        try selectFirstResult()
    }

    func browseAllFrameworks(resetCategory: Bool = true) async throws {
        guard let engine else { return }
        selectedFramework = nil
        searchText = ""
        if resetCategory {
            selectedBrowseCategory = .all
        }
        isLoading = true
        defer { isLoading = false }

        let filter = BrowseFilter(text: browseFilterText, category: selectedBrowseCategory, limit: 500)
        resultSections = try engine.browseFrameworks(filter: filter)
        resultsTitle = "All Frameworks"
        isBrowseMode = true
        try selectFirstResult()
    }

    func browseFramework(_ framework: String) async throws {
        guard let engine else { return }
        selectedFramework = framework
        searchText = ""
        isLoading = true
        defer { isLoading = false }

        let filter = BrowseFilter(text: browseFilterText, category: selectedBrowseCategory, limit: 160)
        resultSections = try engine.browseFramework(framework, filter: filter)
        resultsTitle = framework
        isBrowseMode = true
        try selectFirstResult()
    }

    func refreshBrowseResults() async throws {
        guard isBrowseMode else { return }

        if let framework = try resolvedFrameworkFromBrowseFilter(), selectedFramework != framework {
            browseFilterText = ""
            try await browseFramework(framework)
            return
        }

        if let selectedFramework {
            try await browseFramework(selectedFramework)
        } else {
            try await browseAllFrameworks(resetCategory: false)
        }
    }

    func openFrameworkFilterMatch() async throws {
        guard let engine else { return }
        guard let framework = try engine.matchingFramework(named: frameworkFilterText) else {
            return
        }

        browseFilterText = ""
        try await browseFramework(framework)
    }

    func clearBrowseFilters() async throws {
        browseFilterText = ""
        selectedBrowseCategory = .all
        try await refreshBrowseResults()
    }

    func selectEntry(assetID: String) throws {
        guard let engine else { return }
        selectedEntry = try engine.entry(assetID: assetID)
        relatedResults = try engine.related(assetID: assetID, limit: 12)
        refreshSummary()
    }

    func refreshSummary() {
        guard let selectedEntry else {
            localSummary = ""
            return
        }
        localSummary = summaryGenerator.summary(for: selectedEntry)
    }

    func copyPrimaryContent() {
        guard let selectedEntry else { return }
        let payload = selectedEntry.content ?? selectedEntry.rawDocumentJSON
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(payload, forType: .string)
    }

    func copyAssetID() {
        guard let selectedEntry else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(selectedEntry.assetID, forType: .string)
    }

    private func selectFirstResult() throws {
        if let first = searchResults.first {
            try selectEntry(assetID: first.assetID)
        } else {
            selectedEntry = nil
            relatedResults = []
            localSummary = ""
        }
    }

    private func resolvedFrameworkFromBrowseFilter() throws -> String? {
        guard let engine else { return nil }
        return try engine.matchingFramework(named: browseFilterText)
    }

    private func normalizedFrameworkKey(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
