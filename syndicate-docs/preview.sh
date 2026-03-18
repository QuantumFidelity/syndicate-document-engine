#!/bin/bash
set -euo pipefail

INPUT="${1:-}"

if [ -z "$INPUT" ]; then
  echo "Usage: ./preview.sh documents/file.md"
  echo "Or:    ./preview.sh file.md   # assumes documents/file.md"
  exit 1
fi

# If the user passes just a filename, assume it lives in documents/
if [[ "$INPUT" != */* ]]; then
  INPUT="documents/$INPUT"
fi

if [ ! -f "$INPUT" ]; then
  echo "Error: '$INPUT' not found."
  echo "Available documents:"
  ls documents/*.md 2>/dev/null || echo "  (none in documents/)"
  exit 1
fi

OUTPUT_DIR="output"
mkdir -p "$OUTPUT_DIR"
OUTPUT=$(basename "$INPUT" .md)

pandoc "$INPUT" \
  --from markdown \
  --standalone \
  --template templates/base.html \
  --css templates/styles.css \
  -o "$OUTPUT_DIR/$OUTPUT.html"

open "$OUTPUT_DIR/$OUTPUT.html"
