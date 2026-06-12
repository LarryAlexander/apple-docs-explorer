# Release Guide

This project ships two surfaces:

- `Apple Docs Explorer.app`: the native macOS UI.
- `apple-docs-cli` / `apple-docs-mcp`: command-line and MCP entrypoints that can also run in Docker.

The Docker image is for CLI/MCP usage only. It does not run the macOS GUI.

## Pre-release validation

Run these checks before tagging:

```bash
swift test
swift run DocsCLI diagnose-asset
swift run DocsCLI browse-framework "Accessory Notifications"
./scripts/generate_project.sh
xcodebuild -project AppleDocsExplorer.xcodeproj -scheme AppleDocsExplorer -configuration Release build
docker build -t apple-docs-explorer:local .
```

## Docker image

Build locally:

```bash
docker build -t apple-docs-explorer:0.1.0 .
```

Run diagnostics with a mounted local docs asset:

```bash
docker run --rm \
  -e APPLE_DOCS_ASSET_ROOT=/docs-asset \
  -v /System/Library/AssetsV2/com_apple_MobileAsset_AppleDeveloperDocumentation:/docs-asset:ro \
  apple-docs-explorer:0.1.0 diagnose-asset
```

Run a search:

```bash
docker run --rm \
  -e APPLE_DOCS_ASSET_ROOT=/docs-asset \
  -v /System/Library/AssetsV2/com_apple_MobileAsset_AppleDeveloperDocumentation:/docs-asset:ro \
  apple-docs-explorer:0.1.0 search CloudKit
```

If Docker Desktop blocks `/System/Library` mounts, copy or expose the asset directory through a Docker file-sharing path and point `APPLE_DOCS_ASSET_ROOT` at the mounted location.

## GitHub release checklist

1. Update the README screenshots and release notes.
2. Run the pre-release validation commands.
3. Commit release-ready changes.
4. Tag the release:

```bash
git tag v0.1.0
git push origin v0.1.0
```

5. Build and publish the Docker image:

```bash
docker build -t ghcr.io/LarryAlexander/apple-docs-explorer:0.1.0 .
docker tag ghcr.io/LarryAlexander/apple-docs-explorer:0.1.0 ghcr.io/LarryAlexander/apple-docs-explorer:latest
docker push ghcr.io/LarryAlexander/apple-docs-explorer:0.1.0
docker push ghcr.io/LarryAlexander/apple-docs-explorer:latest
```

6. Create a GitHub release and include:

- macOS app build notes
- Docker image tag
- supported Xcode docs asset version
- known limitations
- screenshot links from `docs/assets/screenshots`
