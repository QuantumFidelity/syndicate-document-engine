#!/bin/bash
set -euo pipefail

INPUT="${1:-}"

if [ -z "$INPUT" ]; then
  echo "Usage: ./build.sh documents/file.md"
  echo "Or:    ./build.sh file.md   # assumes documents/file.md"
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

OUTPUT_DIR="output"
mkdir -p "$OUTPUT_DIR"
OUTPUT=$(basename "$INPUT" .md)
HTML_FILE="$OUTPUT_DIR/$OUTPUT.html"
PDF_FILE="$OUTPUT_DIR/$OUTPUT.pdf"

# Step 1: Pandoc markdown -> HTML (uses our template and CSS)
pandoc "$INPUT" \
  --from markdown \
  --standalone \
  --template templates/base.html \
  --css templates/styles.css \
  -o "$HTML_FILE"

# Step 2: Chrome/Chromium headless print to PDF (paged media, correct pagination)
CHROME=""
for cmd in google-chrome chromium-browser chromium google-chrome-stable; do
  if command -v "$cmd" &>/dev/null; then
    CHROME="$cmd"
    break
  fi
done

if [ -z "$CHROME" ]; then
  echo "Error: No Chrome/Chromium found. Install google-chrome or chromium for PDF output."
  echo "HTML preview saved to: $HTML_FILE"
  exit 1
fi

HTML_ABS="$SCRIPT_DIR/$OUTPUT_DIR/$OUTPUT.html"
"$CHROME" --headless --disable-gpu --no-pdf-header-footer \
  --print-to-pdf="$PDF_FILE" \
  "file://$HTML_ABS" 2>/dev/null || true

if [ -f "$PDF_FILE" ]; then
  echo "PDF built: $PDF_FILE"
  open "$PDF_FILE" 2>/dev/null || xdg-open "$PDF_FILE" 2>/dev/null || true
else
  echo "Warning: PDF generation failed. HTML saved to: $HTML_FILE"
  open "$HTML_FILE" 2>/dev/null || xdg-open "$HTML_FILE" 2>/dev/null || true
  exit 1
fi
