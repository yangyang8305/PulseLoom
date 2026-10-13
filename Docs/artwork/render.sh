#!/bin/bash
# Render four deterministic frames of one option with headless Chrome.
# Usage: render.sh options/<id>.js  → frames/<id>-{idle-light,heart-light,music-light,heart-dark}.png
set -e
cd "$(dirname "$0")"
js="$1"; id=$(basename "$js" .js); mkdir -p frames
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
shot() { # name query
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --window-size=440,470 --force-device-scale-factor=2 \
    --screenshot="frames/$id-$1.png" "file://$PWD/harness.html?js=$js&$2" >/dev/null 2>&1
}
shot idle-light  "t=6000&mode=idle&theme=light"
shot heart-light "t=6040&mode=heart&theme=light"
shot music-light "t=9300&mode=music&theme=light"
shot heart-dark  "t=6040&mode=heart&theme=dark"
ls -1 frames/$id-*.png
