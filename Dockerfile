# Use the official lightweight Node.js image.
FROM node:alpine

# Install pnpm tsx globally
RUN npm install -g pnpm tsx

# Install PowerShell (Alpine/musl build) so the in-image docs-build script and
# CI container jobs can run .ps1 scripts. Microsoft ships a musl tarball plus a
# set of native runtime dependencies that must be present on Alpine.
#
# `tar` is GNU tar, installed over BusyBox's applet on purpose: workflows that
# run inside this image call actions/upload-pages-artifact, which archives with
# `tar --hard-dereference`. BusyBox tar does not accept that flag and fails the
# Pages deploy at the "Archive artifact" step.
ARG POWERSHELL_VERSION=7.4.6
ARG POWERSHELL_SHA256=d5f63653c1cc73a8903d0181bd8616952b4b0e435758d98ee19a617c203c48a8
RUN apk add --no-cache \
        ca-certificates \
        git \
        less \
        ncurses-terminfo-base \
        krb5-libs \
        libgcc \
        libintl \
        libssl3 \
        libstdc++ \
        tzdata \
        userspace-rcu \
        zlib \
        icu-libs \
        curl \
        tar \
    && curl -fSL "https://github.com/PowerShell/PowerShell/releases/download/v${POWERSHELL_VERSION}/powershell-${POWERSHELL_VERSION}-linux-musl-x64.tar.gz" \
        -o /tmp/powershell.tar.gz \
    && echo "${POWERSHELL_SHA256}  /tmp/powershell.tar.gz" | sha256sum -c - \
    && mkdir -p /opt/microsoft/powershell/7 \
    && tar zxf /tmp/powershell.tar.gz -C /opt/microsoft/powershell/7 \
    && chmod +x /opt/microsoft/powershell/7/pwsh \
    && ln -s /opt/microsoft/powershell/7/pwsh /usr/bin/pwsh \
    && rm -f /tmp/powershell.tar.gz

# Make pwsh the default shell for subsequent build-time RUN steps.
SHELL ["pwsh", "-Command", "$ErrorActionPreference = 'Stop';"]

# Create and change to the template directory.
WORKDIR /template

# Copy package files first for better Docker layer caching
COPY package.json pnpm-lock.yaml ./

# Install dependencies
RUN pnpm install --frozen-lockfile; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# Copy the source code into the container.
COPY . ./

# Do not ship template docs in the base image so downstream projects can provide
# their own docs without inherited sample content.
RUN Remove-Item -Recurse -Force /template/docs -ErrorAction SilentlyContinue

# Link this image to its source repository so GHCR lists it under the repo's
# Packages and inherits repo visibility/permissions.
LABEL org.opencontainers.image.source="https://github.com/The-Running-Dev/Docusaurus-Template"
LABEL org.opencontainers.image.description="Docusaurus documentation template base image"
LABEL org.opencontainers.image.licenses="MIT"

# Puts PowerShell/DocusaurusTemplate on the module search path, so any pwsh
# session in this image -- the entrypoint's dispatch, or an interactive
# `docker run -it <image> pwsh` -- can call Invoke-SetupDocs / Invoke-DocsBuild
# directly, auto-loading the module on first use with no explicit
# Import-Module required.
#
# No ${PSModulePath} suffix: ENV substitution only sees prior ARG/ENV values in
# this Dockerfile, not pwsh's own runtime default, so a trailing
# ":${PSModulePath}" here would expand to a bare trailing colon at build time,
# not "append to whatever pwsh already has". pwsh merges its own default
# module paths in ahead of this value at startup regardless (confirmed:
# built-in modules still resolve), so overriding rather than appending is both
# correct and what actually happens either way.
ENV PSModulePath="/template/PowerShell"

# An arbitrary --user UID (as recommended for Invoke-SetupDocs, so written
# files aren't root-owned on the host) has no /etc/passwd entry, so $HOME
# resolves to '/', which is not writable. pwsh then falls back to writing its
# startup-profile cache (StartupProfileData-NonInteractive) into the current
# directory instead -- confirmed by reproduction, and confirmed fixed by
# giving it a writable HOME. /tmp is world-writable (rwxrwxrwt) regardless of
# UID, unlike anywhere under /template, which root owns from the build.
ENV HOME=/tmp

# Expose port 3000
EXPOSE 3000

# entrypoint.sh dispatches on argv[0]: no args (or 'dev') runs start:docker,
# preserving today's bare `docker run <image>` behavior; 'pwsh'/'sh'/'bash'
# exec directly; anything else is looked up as an exported DocusaurusTemplate
# command. Invoked via `/bin/sh <path>` rather than relying on the file's own
# execute bit or shebang, so a COPY that lands without the execute bit still
# runs.
#
# 'dev' needs documentation mounted over /template/docs to serve anything, since
# the docs tree is deleted above. entrypoint.sh checks for that before starting
# and exits with the mount commands to use, instead of letting Docusaurus fail
# with a stack trace and leaving the container running behind it.
# scripts/preview-docs.ps1 is what sets those mounts up.
ENTRYPOINT ["/bin/sh", "/template/scripts/entrypoint.sh"]
CMD ["dev"]
