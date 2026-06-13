#!/usr/bin/env bash
# Render the four form factors of haydn-lowdn into ./outputs/ — a desktop
# screenshot, a mobile screenshot, the print PDF, and the canvas PNG export
# — so you can spot-check that a change works everywhere before pushing.
# Usage: ./snapshot.sh [path/to/index.html]
#
# Runs the four headless-Chrome invocations in parallel — each gets its own
# mktemp user-data-dir so they don't fight over the singleton lock. Sequential
# runs deadlocked in practice (Chrome 149 leaves background processes that
# block the next launch); parallel side-steps that entirely.

DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="${1:-$DIR/index.html}"
OUT="$DIR/outputs"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

mkdir -p "$OUT"

# ----- helpers ---------------------------------------------------------------
shot() {
  local input="$1" output="$2" w="$3" h="$4"
  local ud
  ud="$(mktemp -d)"
  "$CHROME" \
    --headless=new --disable-gpu --no-sandbox \
    --user-data-dir="$ud" \
    --window-size="$w,$h" \
    --hide-scrollbars \
    --virtual-time-budget=4000 \
    --screenshot="$output" \
    "file://$input" >/dev/null 2>&1
  rm -rf "$ud"
}

pdf() {
  local input="$1" output="$2"
  local ud
  ud="$(mktemp -d)"
  "$CHROME" \
    --headless=new --disable-gpu --no-sandbox \
    --user-data-dir="$ud" \
    --no-pdf-header-footer \
    --print-to-pdf="$output" \
    --print-to-pdf-no-header \
    --virtual-time-budget=4000 \
    "file://$input" >/dev/null 2>&1
  rm -rf "$ud"
}

# ----- prep PNG-export test page (toBlob → inline <img>) ---------------------
TEST="$DIR/.snapshot_png.html"
cp "$SRC" "$TEST"
python3 - "$TEST" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
inject = """
<script>
HTMLCanvasElement.prototype.toBlob = function(cb, type) {
  const img = document.createElement('img');
  img.src = this.toDataURL(type || 'image/png');
  img.style.cssText = 'position:absolute;top:0;left:0;width:1300px;z-index:99999;background:#fff';
  document.body.style.padding = '0';
  document.body.innerHTML = '';
  document.body.appendChild(img);
};
window.addEventListener('load', () => setTimeout(() => {
  document.querySelector('[data-action="png"]').click();
}, 600));
</script>
"""
s = s.replace('</body>', inject + '\n</body>')
open(p, 'w').write(s)
PY

# ----- fire all four in parallel ---------------------------------------------
echo "Rendering 4 form factors in parallel…"
shot "$SRC"  "$OUT/desktop.png"    1300 1200 &
shot "$SRC"  "$OUT/mobile.png"      402 1500 &
pdf  "$SRC"  "$OUT/print.pdf"                &
shot "$TEST" "$OUT/png_export.png" 1300 5000 &
wait

rm -f "$TEST"

# ----- report -----------------------------------------------------------------
echo
echo "Output:"
for f in desktop.png mobile.png print.pdf png_export.png; do
  if [ -f "$OUT/$f" ]; then
    printf "  ✓ %-16s %s\n" "$f" "$(ls -lh "$OUT/$f" | awk '{print $5}')"
  else
    printf "  ✗ %-16s MISSING\n" "$f"
  fi
done
