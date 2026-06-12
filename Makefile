.PHONY: test diagnose list-frameworks browse-framework docker-build launch mcp

test:
	swift test

diagnose:
	swift run DocsCLI diagnose-asset

list-frameworks:
	swift run DocsCLI list-frameworks "$(filter)"

browse-framework:
	swift run DocsCLI browse-framework "$(framework)"

docker-build:
	docker build -t apple-docs-explorer:local .

launch:
	./scripts/launch_app.sh

mcp:
	./scripts/serve_mcp.sh
