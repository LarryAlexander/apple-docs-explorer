import DocsCore
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            resultsColumn
        } detail: {
            detailColumn
        }
        .searchable(text: Bindable(model).searchText, prompt: "Search Apple docs")
        .onSubmit(of: .search) {
            runSearch()
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                appTitlePill
            }
        }
        .alert("Error", isPresented: .constant(model.errorMessage != nil), actions: {
            Button("OK") { model.errorMessage = nil }
        }, message: {
            Text(model.errorMessage ?? "")
        })
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            TextField("Filter frameworks", text: Bindable(model).frameworkFilterText)
                .textFieldStyle(.roundedBorder)
                .padding([.horizontal, .top])
                .onSubmit {
                    openFrameworkFilterMatch()
                }

            List(selection: Bindable(model).selectedFramework) {
                Section("Browse Frameworks") {
                    Button("All Frameworks") {
                        Task {
                            try? await model.browseAllFrameworks()
                        }
                    }
                    .buttonStyle(.plain)

                    ForEach(model.filteredFrameworks, id: \.self) { framework in
                        Button(framework) {
                            Task {
                                try? await model.browseFramework(framework)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var appTitlePill: some View {
        VStack(spacing: 1) {
            Text("Apple Docs Explorer")
                .font(.headline.weight(.semibold))
                .lineLimit(1)
            Text(model.assetDescriptor.map { "Xcode \($0.xcodeVersion) • Release \($0.documentationRelease)" } ?? "Offline Apple docs")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .frame(minWidth: 220, maxWidth: 300)
        .background(.thinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(.separator.opacity(0.55), lineWidth: 0.5)
        }
        .fixedSize(horizontal: true, vertical: true)
    }

    private var resultsColumn: some View {
        VStack(spacing: 0) {
            resultsHeader

            List(selection: .constant(model.selectedEntry?.assetID)) {
                ForEach(model.resultSections) { section in
                    Section {
                        ForEach(section.results) { result in
                            resultRow(result)
                        }
                    } header: {
                        HStack {
                            Text(section.title)
                            Spacer()
                            Text("\(section.results.count)")
                        }
                    }
                }
            }
            .overlay {
                if model.isLoading {
                    ProgressView()
                } else if model.resultCount == 0 {
                    ContentUnavailableView("No Results", systemImage: "doc.text.magnifyingglass", description: Text("Try a broader query, a different type filter, or another framework."))
                }
            }
        }
    }

    private var resultsHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(model.resultsTitle)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(model.resultCount == 1 ? "1 result" : "\(model.resultCount) results")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if model.isBrowseMode {
                browseControls
            } else {
                searchControls
            }
        }
        .padding()
    }

    private var browseControls: some View {
        HStack(spacing: 8) {
            TextField("Filter current browse results", text: Bindable(model).browseFilterText)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    refreshBrowse()
                }

            Picker("Type", selection: Bindable(model).selectedBrowseCategory) {
                ForEach(BrowseCategory.allCases) { category in
                    Text(category.displayName).tag(category)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: model.selectedBrowseCategory) {
                refreshBrowse()
            }

            Button("Filter") {
                refreshBrowse()
            }

            if model.hasActiveBrowseFilters {
                Button("Reset") {
                    Task {
                        try? await model.clearBrowseFilters()
                    }
                }
            }
        }
    }

    private var searchControls: some View {
        HStack(spacing: 8) {
            TextField("Search symbols, topics, and frameworks", text: Bindable(model).searchText)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    runSearch()
                }
            Button("Search") {
                runSearch()
            }
        }
    }

    private func resultRow(_ result: SearchResult) -> some View {
        Button {
            try? model.selectEntry(assetID: result.assetID)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(result.title)
                        .font(.headline)
                    Spacer()
                    Text(result.framework)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(result.docType)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(result.snippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private var detailColumn: some View {
        Group {
            if let entry = model.selectedEntry {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(entry.title)
                                .font(.largeTitle)
                            HStack {
                                Label(entry.framework, systemImage: "shippingbox")
                                Label(entry.docType, systemImage: "tag")
                            }
                            .foregroundStyle(.secondary)
                            HStack {
                                Button("Copy Content") {
                                    model.copyPrimaryContent()
                                }
                                Button("Copy Asset ID") {
                                    model.copyAssetID()
                                }
                                Toggle("Local Summary", isOn: Bindable(model).showSummary)
                                    .toggleStyle(.switch)
                            }
                            .padding(.vertical, 4)

                            if model.showSummary, !model.localSummary.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Local Summary")
                                        .font(.headline)
                                    Text(model.localSummary)
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(12)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            }

                            Text(entry.content ?? entry.snippetSource)
                                .font(.body)
                                .textSelection(.enabled)
                        }

                        if !model.relatedResults.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Related")
                                    .font(.title2)
                                ForEach(model.relatedResults) { result in
                                    Button {
                                        try? model.selectEntry(assetID: result.assetID)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(result.title)
                                                .font(.headline)
                                            Text(result.snippet)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Raw Entry Metadata")
                                .font(.title3)
                            Text(entry.rawDocumentJSON)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                    .padding(24)
                }
            } else {
                ContentUnavailableView("Select a Result", systemImage: "doc.richtext", description: Text("Browse a framework or run a search to inspect the local Apple documentation asset."))
            }
        }
    }

    private func refreshBrowse() {
        Task {
            try? await model.refreshBrowseResults()
        }
    }

    private func runSearch() {
        Task {
            try? await model.performSearch()
        }
    }

    private func openFrameworkFilterMatch() {
        Task {
            try? await model.openFrameworkFilterMatch()
        }
    }
}
