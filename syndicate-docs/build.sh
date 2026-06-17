#!/bin/bash
set -euo pipefail

INPUT="${1:-}"

if [ -z "$INPUT" ]; then
  echo "Usage: ./build.sh documents/file.md"
  echo "Or:    ./build.sh file.md   # assumes documents/file.md"
  exit 1
fi

if [[ "$INPUT" != */* ]]; then
  INPUT="documents/$INPUT"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
# shellcheck source=lib/render.sh
source "$SCRIPT_DIR/lib/render.sh"

if [ ! -f "$INPUT" ]; then
  echo "Error: '$INPUT' not found."
  echo "Available documents:"
  ls documents/*.md 2>/dev/null || echo "  (none in documents/)"
  exit 1
fi

OUTPUT_DIR="output"
mkdir -p "$OUTPUT_DIR"
OUTPUT=$(basename "$INPUT" .md)
HTML_FILE="$OUTPUT_DIR/$OUTPUT.html"
PDF_FILE="$OUTPUT_DIR/$OUTPUT.pdf"
TITLE="${OUTPUT//_/ }"

render_html "$INPUT" "$HTML_FILE" "$TITLE"

CHROME="$(find_chrome || true)"
if [ -z "$CHROME" ]; then
  echo "Error: No Chrome/Chromium found. Install google-chrome or chromium for PDF output."
  echo "HTML saved to: $HTML_FILE"
  exit 1
fi

PDF_ABS="$SCRIPT_DIR/$PDF_FILE"
if render_pdf "$SCRIPT_DIR" "$HTML_FILE" "$PDF_ABS" "$CHROME"; then
  echo "PDF built: $PDF_FILE"
  open_in_browser "file://${PDF_ABS}"
else
  echo "Warning: PDF generation failed. HTML saved to: $HTML_FILE"
  exit 1
fi
