# Use the official lightweight Node.js image.
FROM node:alpine

# Install pnpm tsx globally
RUN npm install -g pnpm tsx

# Install PowerShell (Alpine/musl build) so the in-image docs-build script and
# CI container jobs can run .ps1 scripts. Microsoft ships a musl tarball plus a
# set of native runtime dependencies that must be present on Alpine.
ARG POWERSHELL_VERSION=7.4.6
RUN apk add --no-cache \
        ca-certificates \
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
    && curl -L "https://github.com/PowerShell/PowerShell/releases/download/v${POWERSHELL_VERSION}/powershell-${POWERSHELL_VERSION}-linux-musl-x64.tar.gz" \
        -o /tmp/powershell.tar.gz \
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

# Expose port 3000
EXPOSE 3000

# Run the web service on container startup.
# Use start:docker which binds to 0.0.0.0, making it accessible from outside the container
CMD ["sh", "-c", "pnpm run start:docker"]
