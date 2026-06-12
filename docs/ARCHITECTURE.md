# Architecture

Apple Docs Explorer is built around one retrieval backend shared by the app, CLI, and MCP server.

## Boundaries

- `DocsAssetLocator` finds the active Xcode 27 Apple Developer Documentation asset and validates required files.
- `DocsStore` owns read-only SQLite access and is the adapter boundary for Apple's on-disk schema.
- `SearchEngine` owns ranking, filtering, snippet generation, framework browsing, and related-result grouping.
- `AppleDocsExplorer` is the SwiftUI macOS shell.
- `DocsCLI` exposes diagnostics and quick local checks.
- `DocsMCP` exposes compact structured results for coding agents.

## Why this shape

The app reads Apple's installed asset in place instead of ingesting the full corpus into a custom index. That keeps v1 lightweight, avoids duplicating Apple's docs, and makes schema drift easier to isolate. If Xcode changes the asset format, the intended fix area is `DocsAssetLocator` or `DocsStore`, not the app UI or MCP adapter.

## Framework identity

Apple's display names and internal identifiers do not always match. For example, a visible framework name can be `Accessory Notifications` while rows are keyed as `AccessoryNotifications`. Framework lookup therefore normalizes names at the store boundary so browsing, search filters, and related docs resolve the same local entries.
