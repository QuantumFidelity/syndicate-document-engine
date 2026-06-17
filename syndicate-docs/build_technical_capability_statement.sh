#!/bin/bash
set -euo pipefail

INPUT="${1:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

INPUTS_DIR="documents/inputs"
OUTPUT_DIR="documents/output"
mkdir -p "$INPUTS_DIR" "$OUTPUT_DIR"

if [ -z "$INPUT" ]; then
  echo "Usage: ./build_technical_capability_statement.sh documents/inputs/<doc_name>.md"
  echo "Or:    ./build_technical_capability_statement.sh <doc_name>.md   # assumes documents/inputs/<doc_name>.md"
  echo ""
  echo "Output:"
  echo "  documents/output/<doc_name>.html"
  echo "  documents/output/<doc_name>.pdf"
  echo ""
  echo "Available documents:"
  ls "$INPUTS_DIR"/*.md 2>/dev/null | sed 's|.*/||' || echo "  (none in $INPUTS_DIR/)"
  exit 1
fi

if [[ "$INPUT" != */* ]]; then
  INPUT="$INPUTS_DIR/$INPUT"
fi

# shellcheck source=lib/render.sh
source "$SCRIPT_DIR/lib/render.sh"

if [ ! -f "$INPUT" ]; then
  echo "Error: '$INPUT' not found."
  echo ""
  echo "Available documents:"
  ls "$INPUTS_DIR"/*.md 2>/dev/null | sed 's|.*/||' || echo "  (none in $INPUTS_DIR/)"
  exit 1
fi

BASENAME="$(basename "$INPUT" .md)"
HTML_FILE="$OUTPUT_DIR/$BASENAME.html"
PDF_FILE="$OUTPUT_DIR/$BASENAME.pdf"

TITLE="$(python3 - "$INPUT" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
match = re.match(r"^---\s*\n(.*?)\n---", text, re.DOTALL)
if match:
    for line in match.group(1).splitlines():
        if line.strip().startswith("title:"):
            print(line.split(":", 1)[1].strip().strip('"').strip("'"))
            raise SystemExit
for line in text.splitlines():
    if line.startswith("# "):
        print(line[2:].strip())
        raise SystemExit
print(Path(sys.argv[1]).stem.replace("_", " "))
PY
)"

TCS_MD="$(mktemp)"
trap 'rm -f "$TCS_MD"' EXIT

python3 - "$INPUT" "$TCS_MD" <<'PY'
import re
import sys
from pathlib import Path

source = Path(sys.argv[1])
dest = Path(sys.argv[2])
text = source.read_text(encoding="utf-8")

wrapped = re.match(
    r"^```(?:md|markdown)?\s*\n(.*)\n```\s*$",
    text.strip(),
    re.DOTALL | re.IGNORECASE,
)
if wrapped:
    text = wrapped.group(1).strip() + "\n"

dest.write_text(text, encoding="utf-8")
PY

pandoc "$TCS_MD" \
  --from markdown+yaml_metadata_block+fenced_divs+raw_html \
  --standalone \
  --template templates/technical_capability_statement.html \
  --metadata "title=$TITLE" \
  -o "$HTML_FILE"

echo "HTML built: $HTML_FILE"

CHROME="$(find_chrome || true)"
if [ -z "$CHROME" ]; then
  echo "Error: No Chrome/Chromium found. Install google-chrome or chromium for PDF output."
  exit 1
fi

PDF_ABS="$SCRIPT_DIR/$PDF_FILE"
if render_pdf "$SCRIPT_DIR" "$HTML_FILE" "$PDF_ABS" "$CHROME"; then
  echo "PDF built: $PDF_FILE"
else
  echo "Warning: PDF generation failed. HTML saved to: $HTML_FILE"
  exit 1
fi
