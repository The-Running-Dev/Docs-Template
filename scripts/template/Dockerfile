ARG BASE_IMAGE=ghcr.io/the-running-dev/docs-template:latest
FROM ${BASE_IMAGE}

WORKDIR /template

# Replace the template's own authored docs and landing pages. A consumer serves
# documentation from the site root and provides its own homepage.
#
# src/theme/NotFound is deliberately kept. The template's 404 links only to
# routes it is given, so it is safe anywhere, and CI's docs-build.ps1 overlays
# without deleting — stripping it here would make local preview show a different
# 404 than the published site.
RUN rm -rf ./docs ./src/pages

# Overlay this project's configuration and authored Markdown.
COPY . .

CMD ["sh", "-c", "pnpm run start:docker"]
