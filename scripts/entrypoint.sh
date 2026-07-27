#!/bin/sh
# Container entrypoint. Invoked as `/bin/sh /template/scripts/entrypoint.sh`
# (see Dockerfile ENTRYPOINT) so this file's own execute bit and line endings
# never matter -- only correct for /bin/sh to parse, which sh always is.
#
# Three shapes, dispatched on argv[0]:
#   (none) / dev   Run the dev server -- preserves the pre-entrypoint default
#                  of `docker run <image>` with no command.
#   pwsh / sh      Exec directly. Lets `docker run -it <image> pwsh` still
#                  drop into a plain shell for inspection, same as before an
#                  ENTRYPOINT existed.
#   anything else  Treated as a module command name (e.g. Invoke-SetupDocs)
#                  and handed to dispatch.ps1, which imports the
#                  DocsTemplate module and calls it with the remaining
#                  arguments as real PowerShell parameters -- not
#                  string-interpolated into a -Command, which would make
#                  argument quoting a shell-injection surface.
set -e

# The image ships without /template/docs on purpose (see the Dockerfile), so
# the dev server cannot start unless a project's documentation is mounted over
# it. Left to Docusaurus this surfaces as a fifteen-frame stack trace ending in
# 'The docs folder does not exist for version "current"', and worse, the
# container stays up afterwards: start:docker runs the server under
# `concurrently` alongside a config watcher, and the watcher keeps running
# after the server exits, so a completely broken run still looks healthy to
# `docker ps`. Checking first turns both into one actionable message and a
# non-zero exit.
if [ "$#" -eq 0 ] || [ "$1" = "dev" ]; then
    if [ ! -d /template/docs ] || [ -z "$(ls -A /template/docs 2>/dev/null)" ]; then
        cat >&2 <<'NODOCS'
[docs-template] Nothing to serve: /template/docs is empty or absent.

This image deliberately ships without a docs tree, so projects built from it do
not inherit sample content. The dev server has no documentation to render until
a project's own is mounted over it.

To preview a project's documentation:

  docker run --rm -it -p 3000:3000 \
    -v "$PWD/docs/docs:/template/docs" \
    -v "$PWD/docs/docusaurus.config.ts:/template/docusaurus.config.ts" \
    -v "$PWD/docs/sidebar.ts:/template/sidebar.ts" \
    ghcr.io/the-running-dev/docs-template:latest

scripts/preview-docs.ps1 -- or the docs.ps1 that Invoke-SetupDocs installs into
a project -- sets those mounts up for you, and supports -Live for hot reload.

To build a static site instead of serving one:

  docker run --rm -v "$PWD:/work" -w /work \
    ghcr.io/the-running-dev/docs-template:latest \
    Invoke-DocsBuild -SourceDocs /work/docs -OutputPath /work/artifacts/docs

To install the documentation system into a project:

  docker run --rm -v "$PWD:/work" -w /work \
    ghcr.io/the-running-dev/docs-template:latest \
    Invoke-SetupDocs -ProjectDir /work -Title 'My Project'
NODOCS
        exit 1
    fi

    exec pnpm run start:docker
fi

case "$1" in
    pwsh | sh | bash)
        exec "$@"
        ;;
    *)
        exec pwsh -NoLogo -NoProfile -File /template/scripts/dispatch.ps1 "$@"
        ;;
esac
