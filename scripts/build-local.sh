#!/usr/bin/env bash
# ==============================================================================
# Script: build-local.sh
# Purpose: Build custom Wolfi APK packages and Distroless Java OCI Image
#          locally using Melange & Apko (via Docker or local binaries)
# ==============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

IMAGE_TAG="${1:-java21-distroless:latest}"
ARCH="${ARCH:-$(uname -m)}"

# Normalize arch for apko/melange
case "${ARCH}" in
  x86_64) APK_ARCH="x86_64" ;;
  aarch64|arm64) APK_ARCH="aarch64" ;;
  *) echo "Unsupported architecture: ${ARCH}"; exit 1 ;;
esac

echo "========================================================================"
echo " Building Chainguard-Grade Wolfi Distroless Java Base Image"
echo " Arch: ${APK_ARCH} | Target Image: ${IMAGE_TAG}"
echo "========================================================================"

mkdir -p "${ROOT_DIR}/packages/${APK_ARCH}"
mkdir -p "${ROOT_DIR}/output"

# Step 1: Generate Melange Signing Key if not exists
if [ ! -f "${ROOT_DIR}/melange.rsa" ]; then
  echo "==> [1/3] Generating Melange signing key..."
  if command -v melange &>/dev/null; then
    melange keygen melange.rsa
  else
    docker run --rm -v "${ROOT_DIR}:/work" -w /work \
      cgr.dev/chainguard/melange:latest keygen melange.rsa
  fi
fi

# Step 2: Build Custom JRE package with Melange
echo "==> [2/3] Building Custom JRE APK with Melange..."
if command -v melange &>/dev/null; then
  melange build melange/melange.yaml \
    --arch "${APK_ARCH}" \
    --signing-key melange.rsa \
    --out-dir packages
else
  docker run --rm --privileged \
    -v "${ROOT_DIR}:/work" \
    -w /work \
    cgr.dev/chainguard/melange:latest build melange/melange.yaml \
      --arch "${APK_ARCH}" \
      --signing-key melange.rsa \
      --out-dir packages
fi

# Step 3: Build Distroless OCI Image with Apko
echo "==> [3/3] Building Distroless Container Image with Apko..."
TARBALL="${ROOT_DIR}/output/image-${APK_ARCH}.tar"

if command -v apko &>/dev/null; then
  apko build apko/apko.yaml "${IMAGE_TAG}" "${TARBALL}" \
    --arch "${APK_ARCH}" \
    --keyring-append melange.rsa.pub
else
  docker run --rm \
    -v "${ROOT_DIR}:/work" \
    -w /work \
    cgr.dev/chainguard/apko:latest build apko/apko.yaml "${IMAGE_TAG}" "${TARBALL}" \
      --arch "${APK_ARCH}" \
      --keyring-append melange.rsa.pub
fi

echo "==> Loading OCI image into Docker daemon..."
LOAD_OUTPUT=$(docker load < "${TARBALL}")
echo "${LOAD_OUTPUT}"

LOADED_TAG=$(echo "${LOAD_OUTPUT}" | awk -F': ' '/Loaded image/ {print $2}')
if [ -n "${LOADED_TAG}" ] && [ "${LOADED_TAG}" != "${IMAGE_TAG}" ]; then
  docker tag "${LOADED_TAG}" "${IMAGE_TAG}"
fi

echo "========================================================================"
echo " [SUCCESS] Distroless image loaded: ${IMAGE_TAG}"
echo " Test with: docker run --rm ${IMAGE_TAG} -version"
echo "========================================================================"
