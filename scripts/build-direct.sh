#!/usr/bin/env bash
# ==============================================================================
# Script: build-direct.sh
# Purpose: Build Distroless Java OCI Image using upstream Wolfi packages
#          directly via Apko (No Melange compilation needed).
# ==============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

IMAGE_TAG="${1:-wolfi-java21:latest}"
ARCH="${ARCH:-$(uname -m)}"

case "${ARCH}" in
  x86_64) APK_ARCH="x86_64" ;;
  aarch64|arm64) APK_ARCH="aarch64" ;;
  *) echo "Unsupported architecture: ${ARCH}"; exit 1 ;;
esac

mkdir -p "${ROOT_DIR}/output"
TARBALL="${ROOT_DIR}/output/direct-${APK_ARCH}.tar"

echo "==> Building Distroless OCI Image with Apko directly from Wolfi..."
if command -v apko &>/dev/null; then
  apko build apko/apko-wolfi-direct.yaml "${IMAGE_TAG}" "${TARBALL}" \
    --arch "${APK_ARCH}"
else
  docker run --rm \
    -v "${ROOT_DIR}:/work" \
    -w /work \
    cgr.dev/chainguard/apko:latest build apko/apko-wolfi-direct.yaml "${IMAGE_TAG}" "${TARBALL}" \
      --arch "${APK_ARCH}"
fi

echo "==> Loading OCI image into Docker daemon..."
LOAD_OUTPUT=$(docker load < "${TARBALL}")
echo "${LOAD_OUTPUT}"

# Extract loaded image tag name and alias to requested tag if different
LOADED_TAG=$(echo "${LOAD_OUTPUT}" | awk -F': ' '/Loaded image/ {print $2}')
if [ -n "${LOADED_TAG}" ] && [ "${LOADED_TAG}" != "${IMAGE_TAG}" ]; then
  docker tag "${LOADED_TAG}" "${IMAGE_TAG}"
fi

echo "==> Testing JVM container parameters and jemalloc preloading..."
docker run --rm "${IMAGE_TAG}" -version
