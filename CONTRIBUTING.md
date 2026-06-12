# Contributing to Apple Docs Explorer

Apple Docs Explorer is intentionally small: a native macOS reader, a shared local retrieval core, and an optional MCP server for agents. Contributions should keep that shape intact.

## Local setup

Requirements:

- macOS 15 or newer
- Xcode 27 with the Apple Developer Documentation asset installed
- Swift 6.2 or newer
- XcodeGen if you want to regenerate the Xcode project
- Docker Desktop only if you want to test the CLI/MCP container

Useful commands:

```bash
swift test
swift run DocsCLI diagnose-asset
swift run DocsCLI list-frameworks cloudkit
swift run DocsCLI browse-framework "Accessory Notifications"
./scripts/generate_project.sh
./scripts/launch_app.sh
./scripts/serve_mcp.sh
```

## Code expectations

- Warnings are treated as errors.
- Keep Apple asset schema assumptions inside `DocsStore` and `DocsAssetLocator`.
- Do not copy Apple's documentation corpus into this repository.
- Keep the MCP server as a thin adapter over `SearchEngine`; retrieval logic belongs in `DocsCore`.
- Prefer focused patches with tests for ranking, filtering, asset detection, or MCP payload shape.

## Good first issues

- Improve browse grouping for specific frameworks.
- Add tests for framework-name normalization edge cases.
- Improve snippets for symbol-heavy results.
- Add release packaging automation for the macOS app.
- Document verified Xcode documentation asset versions.

## Reporting bugs

Please include:

- macOS version
- Xcode version
- output from `swift run DocsCLI diagnose-asset`
- framework or search query that failed
- whether the issue appears in the GUI, CLI, MCP server, or all three

If a framework shows in the sidebar but has no results, include the exact visible framework name. Those bugs usually mean Apple's display name and internal module identifier drifted.
