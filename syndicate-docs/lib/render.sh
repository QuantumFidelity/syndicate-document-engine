#!/bin/bash
# Shared render helpers for preview.sh and build.sh

find_chrome() {
  local candidates=(
    /opt/google/chrome/chrome
    /opt/google/chrome/google-chrome
    /usr/bin/google-chrome-stable
    /usr/bin/chromium
    /usr/bin/chromium-browser
  )
  local cmd
  for cmd in "${candidates[@]}"; do
    if [[ -x "$cmd" ]]; then
      echo "$cmd"
      return 0
    fi
  done
  return 1
}

render_html() {
  local input="$1"
  local html_file="$2"
  local title="$3"

  pandoc "$input" \
    --from markdown \
    --standalone \
    --template templates/base.html \
    --css templates/styles.css \
    --metadata "title=$title" \
    -o "$html_file"
}

validate_pdf() {
  local pdf_file="$1"

  if [[ ! -s "$pdf_file" ]]; then
    echo "Error: PDF is missing or empty: $pdf_file" >&2
    return 1
  fi

  if ! head -c 5 "$pdf_file" | grep -q '%PDF'; then
    echo "Error: File is not a valid PDF (bad header): $pdf_file" >&2
    return 1
  fi

  if ! tail -c 16 "$pdf_file" | grep -q '%%EOF'; then
    echo "Error: PDF is incomplete (missing %%EOF): $pdf_file" >&2
    return 1
  fi

  if command -v pdfinfo &>/dev/null; then
    if ! pdfinfo "$pdf_file" &>/dev/null; then
      echo "Error: pdfinfo could not read PDF: $pdf_file" >&2
      return 1
    fi
  fi

  return 0
}

# Poppler/Evince-safe pass: flatten structure, drop transparency artifacts.
# Chrome PDFium tolerates more than Document Viewer (Poppler).
optimize_pdf() {
  local pdf_file="$1"
  local tmp="${pdf_file}.opt.pdf"

  if command -v mutool &>/dev/null; then
    if mutool clean -gggg -d "$pdf_file" "$tmp" 2>/dev/null && [[ -s "$tmp" ]]; then
      mv -f "$tmp" "$pdf_file"
      return 0
    fi
    rm -f "$tmp"
  fi

  if command -v gs &>/dev/null; then
    if gs -q -sDEVICE=pdfwrite \
      -dCompatibilityLevel=1.4 \
      -dPDFSETTINGS=/ebook \
      -dColorConversionStrategy=/RGB \
      -dProcessColorModel=/DeviceRGB \
      -dUseCIEColor=false \
      -dAutoRotatePages=/None \
      -dNOPAUSE -dBATCH -dSAFER \
      -sOutputFile="$tmp" "$pdf_file" 2>/dev/null && [[ -s "$tmp" ]]; then
      mv -f "$tmp" "$pdf_file"
      return 0
    fi
    rm -f "$tmp"
  fi

  return 0
}

render_pdf() {
  local script_dir="$1"
  local html_file="$2"
  local pdf_file="$3"
  local chrome="$4"

  pdf_file="$(cd "$(dirname "$pdf_file")" && pwd)/$(basename "$pdf_file")"
  rm -f "$pdf_file"

  local port
  port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()')"
  python3 -m http.server "$port" --directory "$script_dir" >/dev/null 2>&1 &
  local server_pid=$!

  cleanup() {
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  }
  trap cleanup EXIT

  local preview_url
  preview_url="$(python3 -c "import urllib.parse; print('http://127.0.0.1:${port}/' + urllib.parse.quote('${html_file}', safe='/'))")"

  local ready=0
  local i
  for i in $(seq 1 25); do
    if curl -sf "$preview_url" -o /dev/null 2>/dev/null; then
      ready=1
      break
    fi
    sleep 0.2
  done

  if [[ "$ready" -ne 1 ]]; then
    echo "Error: Could not load HTML for PDF export: $preview_url" >&2
    return 1
  fi

  if ! "$chrome" \
    --headless=new \
    --disable-gpu \
    --no-sandbox \
    --disable-pdf-tagging \
    --no-pdf-header-footer \
    --run-all-compositor-stages-before-draw \
    --virtual-time-budget=15000 \
    --print-to-pdf="$pdf_file" \
    "$preview_url" 2>&1; then
    echo "Error: Chrome failed to generate PDF." >&2
    return 1
  fi

  cleanup
  trap - EXIT

  validate_pdf "$pdf_file"
}

file_uri() {
  python3 -c "from pathlib import Path; print(Path('$1').resolve().as_uri())"
}

open_in_browser() {
  local target="$1"
  local uri

  if [[ "$target" == /* ]]; then
    uri="$(file_uri "$target")"
  else
    uri="$target"
  fi

  if [ -n "${PREVIEW_BROWSER:-}" ]; then
    "$PREVIEW_BROWSER" "$uri" >/dev/null 2>&1 &
    echo "Opened in $PREVIEW_BROWSER"
    return 0
  fi

  case "$(uname -s)" in
    Darwin)
      open "$target"
      echo "Opened in default application"
      return 0
      ;;
  esac

  local cmd
  for cmd in google-chrome-stable /opt/google/chrome/chrome google-chrome chromium chromium-browser firefox brave-browser; do
    if [[ -x "$cmd" ]] || command -v "$cmd" &>/dev/null; then
      "$cmd" "$uri" >/dev/null 2>&1 &
      echo "Opened in $(basename "$cmd")"
      return 0
    fi
  done

  echo "Could not open automatically. Open this file in your PDF viewer:"
  echo "  $target"
  echo "  $uri"
  return 1
}
