import Foundation

public final class SearchEngine: @unchecked Sendable {
    private let store: DocsProviding

    public init(store: DocsProviding) {
        self.store = store
    }

    public func search(_ query: SearchQuery) throws -> SearchResponse {
        let entries = try store.searchDocuments(query: query)
        let ranked = rank(entries: entries, query: query)
        return SearchResponse(query: query, results: Array(ranked.prefix(query.limit)))
    }

    public func frameworks(limit: Int = 200) throws -> [String] {
        try store.frameworks(limit: limit)
    }

    public func matchingFramework(named input: String) throws -> String? {
        let query = normalizedFrameworkName(input)
        guard !query.isEmpty else { return nil }

        let frameworks = try store.frameworks(limit: 1_000)
        if let exact = frameworks.first(where: { normalizedFrameworkName($0) == query }) {
            return exact
        }

        let matches = frameworks.filter { normalizedFrameworkName($0).contains(query) }
        guard matches.count == 1 else {
            return nil
        }
        return matches.first
    }

    public func browseFrameworks(limit: Int = 200) throws -> [SearchResult] {
        try browseFrameworks(filter: BrowseFilter(limit: limit)).flatMap(\.results)
    }

    public func browseFrameworks(filter: BrowseFilter = BrowseFilter()) throws -> [BrowseSection] {
        let filterText = filter.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let fetchLimit = max(filter.limit * 20, filter.limit)

        if filter.category != .all && filter.category != .frameworks {
            let entries = try store.browseEntries(category: filter.category, limit: fetchLimit)
            let filtered = filterEntries(entries, filter: filter)
                .sorted { lhs, rhs in
                    let lhsScore = browseScore(entry: lhs, selectedFramework: lhs.framework, filterText: filterText)
                    let rhsScore = browseScore(entry: rhs, selectedFramework: rhs.framework, filterText: filterText)
                    if lhsScore == rhsScore {
                        return lhs.framework.localizedCaseInsensitiveCompare(rhs.framework) == .orderedAscending
                    }
                    return lhsScore > rhsScore
                }
            return groupEntriesByFramework(Array(filtered.prefix(max(filter.limit, 0))))
        }

        let entries: [DocEntry]
        if filterText.isEmpty {
            entries = try store.frameworkOverviewEntries(limit: max(filter.limit, 0))
        } else {
            entries = try store.searchDocuments(query: SearchQuery(text: filterText, limit: fetchLimit))
        }

        let filtered = filterEntries(entries, filter: filter)
            .sorted { lhs, rhs in
                if !filterText.isEmpty {
                    let lhsScore = browseScore(entry: lhs, selectedFramework: lhs.framework, filterText: filterText)
                    let rhsScore = browseScore(entry: rhs, selectedFramework: rhs.framework, filterText: filterText)
                    if lhsScore != rhsScore {
                        return lhsScore > rhsScore
                    }
                }
                return lhs.framework.localizedCaseInsensitiveCompare(rhs.framework) == .orderedAscending
            }

        if !filterText.isEmpty {
            return groupFrameworkEntries(Array(filtered.prefix(max(filter.limit, 0))))
        }

        return groupFrameworkOverviews(filtered.prefix(max(filter.limit, 0)).map { result(for: $0) })
    }

    public func entries(inFramework framework: String, limit: Int = 200) throws -> [DocEntry] {
        try store.entries(inFramework: framework, limit: limit)
    }

    public func browseFramework(_ framework: String, limit: Int = 100) throws -> [SearchResult] {
        try browseFramework(framework, filter: BrowseFilter(limit: limit)).flatMap(\.results)
    }

    public func browseFramework(_ framework: String, filter: BrowseFilter = BrowseFilter(limit: 120)) throws -> [BrowseSection] {
        let trimmedFilter = filter.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let fetchLimit = max(filter.limit * 20, 1_200)
        let entries: [DocEntry]
        if trimmedFilter.isEmpty {
            entries = try store.entries(inFramework: framework, limit: fetchLimit)
        } else {
            entries = try store.searchDocuments(query: SearchQuery(text: trimmedFilter, framework: framework, limit: fetchLimit))
        }

        let filtered = filterEntries(entries, filter: filter)
            .sorted { lhs, rhs in
                let lhsScore = browseScore(entry: lhs, selectedFramework: framework, filterText: trimmedFilter)
                let rhsScore = browseScore(entry: rhs, selectedFramework: framework, filterText: trimmedFilter)
                if lhsScore == rhsScore {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                return lhsScore > rhsScore
            }

        return groupFrameworkEntries(Array(filtered.prefix(max(filter.limit, 0))))
    }

    public func entry(assetID: String) throws -> DocEntry? {
        try store.entry(assetID: assetID)
    }

    public func related(assetID: String, limit: Int = 10) throws -> [SearchResult] {
        let entries = try store.relatedEntries(assetID: assetID, limit: limit)
        return entries.map {
            SearchResult(
                assetID: $0.assetID,
                title: $0.title,
                framework: $0.framework,
                docType: $0.docType,
                snippet: makeSnippet(for: $0, query: nil),
                score: 0
            )
        }
    }

    public func lookupSymbol(name: String, framework: String? = nil, limit: Int = 20) throws -> SearchResponse {
        try search(SearchQuery(text: name, framework: framework, limit: limit))
    }

    public func assetDescriptor() throws -> DocsAssetDescriptor {
        try store.assetDescriptor()
    }

    private func rank(entries: [DocEntry], query: SearchQuery) -> [SearchResult] {
        let tokens = tokenize(query.text)
        return entries
            .map { entry in
                let score = score(entry: entry, rawQuery: query.text, tokens: tokens, framework: query.framework)
                return SearchResult(
                    assetID: entry.assetID,
                    title: entry.title,
                    framework: entry.framework,
                    docType: entry.docType,
                    snippet: makeSnippet(for: entry, query: query.text),
                    score: score
                )
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                return lhs.score > rhs.score
            }
    }

    private func filterEntries(_ entries: [DocEntry], filter: BrowseFilter) -> [DocEntry] {
        let filterText = filter.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return entries.filter { entry in
            guard filter.category.matches(entry) else {
                return false
            }

            guard !filterText.isEmpty else {
                return true
            }

            let searchableText = [
                entry.title,
                entry.framework,
                entry.docType,
                entry.assetID,
                entry.metadata.symbol?.preciseIdentifier,
                entry.content
            ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

            return searchableText.contains(filterText)
        }
    }

    private func browseScore(entry: DocEntry, selectedFramework: String, filterText: String) -> Int {
        var total = 0

        if entry.framework.caseInsensitiveCompare(selectedFramework) == .orderedSame {
            total += 100
        }

        switch BrowseCategory.category(for: entry) {
        case .frameworks:
            total += 1_000
        case .topics:
            total += 850
        case .articles:
            total += 750
        case .tutorials:
            total += 700
        case .samples:
            total += 650
        case .symbols:
            total += 250
        case .other:
            total += 100
        case .all:
            break
        }

        if entry.title.caseInsensitiveCompare(selectedFramework) == .orderedSame {
            total += 600
        }

        guard !filterText.isEmpty else {
            return total
        }

        let query = filterText.lowercased()
        let title = entry.title.lowercased()
        let assetID = entry.assetID.lowercased()
        let symbolID = entry.metadata.symbol?.preciseIdentifier?.lowercased() ?? ""

        if title == query { total += 500 }
        if title.contains(query) { total += 300 }
        if assetID.contains(query) { total += 180 }
        if symbolID.contains(query) { total += 220 }

        for token in tokenize(query) where !token.isEmpty {
            if title.contains(token) { total += 70 }
            if assetID.contains(token) { total += 40 }
            if symbolID.contains(token) { total += 60 }
        }

        return total
    }

    private func result(for entry: DocEntry) -> SearchResult {
        SearchResult(
            assetID: entry.assetID,
            title: entry.title,
            framework: entry.framework,
            docType: entry.docType,
            snippet: makeSnippet(for: entry, query: nil),
            score: 0
        )
    }

    private func groupFrameworkOverviews(_ results: [SearchResult]) -> [BrowseSection] {
        let grouped = Dictionary(grouping: results) { result in
            result.framework.first.map { String($0).uppercased() } ?? "#"
        }

        return grouped.keys.sorted().map { key in
            BrowseSection(
                id: "frameworks-\(key)",
                title: key,
                results: grouped[key] ?? []
            )
        }
    }

    private func groupFrameworkEntries(_ entries: [DocEntry]) -> [BrowseSection] {
        let grouped = Dictionary(grouping: entries) { entry in
            sectionDescriptor(for: entry).id
        }

        let orderedDescriptors = BrowseSectionDescriptor.ordered
        return orderedDescriptors.compactMap { descriptor in
            guard let sectionEntries = grouped[descriptor.id], !sectionEntries.isEmpty else {
                return nil
            }
            let sectionResults = sectionEntries.map { result(for: $0) }
            return BrowseSection(id: descriptor.id, title: descriptor.title, results: sectionResults)
        }
    }

    private func groupEntriesByFramework(_ entries: [DocEntry]) -> [BrowseSection] {
        let grouped = Dictionary(grouping: entries, by: \.framework)
        return grouped.keys.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }.map { framework in
            let sectionEntries = grouped[framework] ?? []
            return BrowseSection(
                id: "framework-\(framework)",
                title: framework,
                results: sectionEntries.map { result(for: $0) }
            )
        }
    }

    private func sectionDescriptor(for entry: DocEntry) -> BrowseSectionDescriptor {
        switch BrowseCategory.category(for: entry) {
        case .frameworks:
            return .overview
        case .topics:
            return .topics
        case .articles:
            return .articles
        case .tutorials:
            return .tutorials
        case .samples:
            return .samples
        case .symbols:
            return .symbols
        case .other, .all:
            return .other
        }
    }

    private func score(entry: DocEntry, rawQuery: String, tokens: [String], framework: String?) -> Int {
        let query = rawQuery.lowercased()
        let title = entry.title.lowercased()
        let originalTitle = entry.title
        let assetID = entry.assetID.lowercased()
        let type = entry.docType.lowercased()
        let symbolID = entry.metadata.symbol?.preciseIdentifier?.lowercased() ?? ""

        var total = 0
        if originalTitle == rawQuery { total += 900 }
        if title == query { total += 600 }
        if assetID.hasSuffix("/\(query)") { total += 450 }
        if title.contains(query) { total += 300 }
        if assetID.contains(query) { total += 220 }
        if symbolID.contains(query) { total += 320 }
        if type.contains(query) { total += 120 }
        if let framework, entry.framework.caseInsensitiveCompare(framework) == .orderedSame { total += 200 }

        for token in tokens where !token.isEmpty {
            if title.contains(token) { total += 80 }
            if assetID.contains(token) { total += 60 }
            if symbolID.contains(token) { total += 75 }
            if type.contains(token) { total += 20 }
        }

        if entry.metadata.role == "symbol" { total += 50 }
        return total
    }

    private func makeSnippet(for entry: DocEntry, query: String?) -> String {
        let base = entry.snippetSource
        guard let query, !query.isEmpty else {
            return base
        }

        let lowered = base.lowercased()
        let search = query.lowercased()
        guard let range = lowered.range(of: search) else {
            return base
        }

        let lowerBound = max(base.distance(from: base.startIndex, to: range.lowerBound) - 60, 0)
        let upperBound = min(base.distance(from: base.startIndex, to: range.upperBound) + 100, base.count)
        let start = base.index(base.startIndex, offsetBy: lowerBound)
        let end = base.index(base.startIndex, offsetBy: upperBound)
        return String(base[start..<end])
    }

    private func tokenize(_ input: String) -> [String] {
        input
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    private func normalizedFrameworkName(_ input: String) -> String {
        input
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }
}

private struct BrowseSectionDescriptor {
    let id: String
    let title: String

    static let overview = BrowseSectionDescriptor(id: "overview", title: "Framework Overview")
    static let topics = BrowseSectionDescriptor(id: "topics", title: "Topics")
    static let articles = BrowseSectionDescriptor(id: "articles", title: "Articles")
    static let tutorials = BrowseSectionDescriptor(id: "tutorials", title: "Tutorials")
    static let samples = BrowseSectionDescriptor(id: "samples", title: "Sample Code")
    static let symbols = BrowseSectionDescriptor(id: "symbols", title: "Symbols")
    static let other = BrowseSectionDescriptor(id: "other", title: "Other")

    static let ordered = [
        overview,
        topics,
        articles,
        tutorials,
        samples,
        symbols,
        other
    ]
}
