#!/usr/bin/env bash
# ==============================================================================
# Script: generate-appcds.sh
# Purpose: Generate an Application Class Data Sharing (AppCDS) archive
#          for low-latency cold-start and reduced memory footprint across pods.
# Compatibility: OpenJDK 17, 21+
# ==============================================================================
set -euo pipefail

JAR_PATH="${1:-/app/app.jar}"
OUTPUT_ARCHIVE="${2:-/app/app-cds.jsa}"
TEMP_CLASSLIST="/tmp/appcds.classlist"

if [ ! -f "${JAR_PATH}" ]; then
  echo "[ERROR] JAR file not found at: ${JAR_PATH}" >&2
  echo "Usage: $0 <path-to-jar> [output-archive-path]" >&2
  exit 1
fi

echo "==> [AppCDS] Step 1: Performing trial warmup run to record loaded classes..."
# Run the application briefly in training mode to capture loaded classes into classlist
# We can also use Dynamic CDS (-XX:ArchiveClassesAtExit) directly in Java 17/21+
java -Dspring.context.exit=onRefresh \
     -Dserver.port=0 \
     -XX:ArchiveClassesAtExit="${OUTPUT_ARCHIVE}" \
     -jar "${JAR_PATH}" || true

if [ -f "${OUTPUT_ARCHIVE}" ]; then
  echo "==> [AppCDS] Dynamic archive successfully generated at: ${OUTPUT_ARCHIVE}"
  ls -lh "${OUTPUT_ARCHIVE}"
  exit 0
fi

echo "==> [AppCDS] Fallback: Generating AppCDS via ClassList extraction..."
java -Xshare:off \
     -XX:DumpLoadedClassList="${TEMP_CLASSLIST}" \
     -Dspring.context.exit=onRefresh \
     -jar "${JAR_PATH}" || true

echo "==> [AppCDS] Step 2: Creating AppCDS shared archive..."
java -Xshare:dump \
     -XX:SharedClassListFile="${TEMP_CLASSLIST}" \
     -XX:SharedArchiveFile="${OUTPUT_ARCHIVE}" \
     -cp "${JAR_PATH}"

rm -f "${TEMP_CLASSLIST}"
echo "==> [AppCDS] Archive successfully generated at: ${OUTPUT_ARCHIVE}"
ls -lh "${OUTPUT_ARCHIVE}"
