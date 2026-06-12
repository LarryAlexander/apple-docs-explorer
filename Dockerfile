# syntax=docker/dockerfile:1

ARG SWIFT_VERSION=6.2

FROM swift:${SWIFT_VERSION}-jammy AS build

RUN apt-get update \
    && apt-get install -y --no-install-recommends libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

COPY Package.swift ./
COPY Packages ./Packages

RUN swift build -c release --product DocsCLI \
    && swift build -c release --product DocsMCP

FROM swift:${SWIFT_VERSION}-jammy AS runtime

RUN apt-get update \
    && apt-get install -y --no-install-recommends libsqlite3-0 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /workspace/.build/release/DocsCLI /usr/local/bin/apple-docs-cli
COPY --from=build /workspace/.build/release/DocsMCP /usr/local/bin/apple-docs-mcp

ENV APPLE_DOCS_ASSET_ROOT=/docs-asset
VOLUME ["/docs-asset"]

ENTRYPOINT ["apple-docs-cli"]
CMD ["diagnose-asset"]
