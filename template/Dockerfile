# Example Dockerfile for extending the published docs-template image.
# The base image already uses /template as its workdir.
# Replace BASE_IMAGE if you want to target a specific tag or registry path.

ARG BASE_IMAGE=ghcr.io/the-running-dev/docs-template:latest
FROM ${BASE_IMAGE}

WORKDIR /template

# Copy local files over the base image so project-specific files override the
# image contents where paths overlap.
COPY . .

# Reinstall after copy so local package/lockfile changes fully replace the
# dependency graph from the base image.
RUN pnpm install --frozen-lockfile

# Keep the base image startup command unless this derived image needs custom behavior.
CMD ["sh", "-c", "pnpm run start:docker"]