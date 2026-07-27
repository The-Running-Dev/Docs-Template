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
#                  DocusaurusTemplate module and calls it with the remaining
#                  arguments as real PowerShell parameters -- not
#                  string-interpolated into a -Command, which would make
#                  argument quoting a shell-injection surface.
set -e

if [ "$#" -eq 0 ] || [ "$1" = "dev" ]; then
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
