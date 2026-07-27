ARG BASE_IMAGE=ghcr.io/the-running-dev/docs-template:latest
FROM ${BASE_IMAGE}

WORKDIR /template

# Belt-and-braces, not the primary defence. The base image no longer ships
# either directory -- .dockerignore excludes them there -- and docs-build.ps1
# strips any src/pages a stale image still carries before it builds. This line
# does the same for local preview, so a preview against an older pinned
# -BaseImage matches what CI would publish rather than showing routes the
# published site does not have. The two paths disagreeing about this is what
# let the template's own pages reach consumer sites unnoticed.
#
# src/theme/NotFound is deliberately kept: the template's 404 links only to
# routes it is given, so it is safe anywhere, and removing it here would make
# local preview show a different 404 than the published site.
RUN rm -rf ./docs ./src/pages

# Overlay this project's configuration and authored Markdown.
COPY . .

CMD ["sh", "-c", "pnpm run start:docker"]
