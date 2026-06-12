# Screenshots

Screenshots in this folder are intended for the README, GitHub repository preview, and release notes.

Current images:

- `docs/assets/brand/apple-docs-explorer-app-icon.png`: generated app icon source image.
- `docs/assets/brand/apple-docs-explorer-social-card.png`: public README/social preview image.
- `docs/assets/screenshots/apple-docs-explorer-browse.png`: main browse/detail split view.
- `docs/assets/screenshots/apple-docs-explorer-framework-empty-state-before-fix.png`: regression evidence for the framework display-name mismatch fixed in v0.1.0.

Before a public release, refresh the main screenshot after launching the latest build:

```bash
./scripts/launch_app.sh
```

Then capture a clean window screenshot and replace `apple-docs-explorer-browse.png`.
