import DocsCore
import Foundation

#if os(Linux)
import Glibc
#else
import Darwin
#endif

@main
struct DocsCLIApp {
    static func main() async {
        do {
            let store = try DocsStore()
            let engine = SearchEngine(store: store)
            let arguments = Array(CommandLine.arguments.dropFirst())

            if arguments.first == "diagnose-asset" {
                let descriptor = try engine.assetDescriptor()
                print("asset_root=\(descriptor.assetURL.path)")
                print("xcode_version=\(descriptor.xcodeVersion)")
                print("documentation_release=\(descriptor.documentationRelease)")
                print("os_version=\(descriptor.osVersion)")
                return
            }

            if arguments.first == "search", arguments.count >= 2 {
                let query = arguments.dropFirst().joined(separator: " ")
                let response = try engine.search(SearchQuery(text: query, limit: 10))
                for result in response.results {
                    print("\(result.framework)\t\(result.docType)\t\(result.assetID)")
                }
                return
            }

            if arguments.first == "list-frameworks" {
                let filter = arguments.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                let frameworks = try engine.frameworks(limit: 1_000).filter { framework in
                    filter.isEmpty || framework.localizedCaseInsensitiveContains(filter) || normalizedFrameworkKey(framework).contains(normalizedFrameworkKey(filter))
                }
                for framework in frameworks {
                    print(framework)
                }
                return
            }

            if arguments.first == "browse-framework", arguments.count >= 2 {
                let framework = arguments.dropFirst().joined(separator: " ")
                let sections = try engine.browseFramework(framework, filter: BrowseFilter(limit: 25))
                for section in sections {
                    print("# \(section.title)")
                    for result in section.results {
                        print("\(result.framework)\t\(result.docType)\t\(result.title)\t\(result.assetID)")
                    }
                }
                return
            }

            print("Usage:")
            print("  swift run DocsCLI diagnose-asset")
            print("  swift run DocsCLI list-frameworks [filter]")
            print("  swift run DocsCLI browse-framework <framework>")
            print("  swift run DocsCLI search <query>")
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func normalizedFrameworkKey(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
