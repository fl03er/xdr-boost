#!/bin/zsh
# Rebuilds promo/assets (panel, hero and icon frames) from the real app code, then the video:
#   ./make-assets.sh && node render.mjs xdr-boost-promo.mp4
# Needs Xcode command line tools, ffmpeg, and puppeteer-core (npm i puppeteer-core) next to render.mjs.
set -e
cd "$(dirname "$0")"
RAW=$(mktemp -d)
FLAGS=(-O -target "$(uname -m)-apple-macos13.0" -framework AppKit -framework Metal -framework MetalKit -framework ServiceManagement)
swiftc $FLAGS $(ls ../Sources/*.swift | grep -v main.swift) capture-assets.swift -o "$RAW/cap"
"$RAW/cap" "$RAW"
mkdir -p assets/hero assets/panel assets/icon
for f in "$RAW"/on*.png; do
  n=$(basename $f .png)
  ffmpeg -v error -y -i $f -vf "crop=1136:688:72:248" -q:v 2 assets/hero/${n#on}.jpg
  ffmpeg -v error -y -i $f -vf "scale=640:-1:flags=lanczos" assets/panel/${n#on}.png
done
ffmpeg -v error -y -i "$RAW/off.png" -vf "crop=1136:688:72:248" -q:v 2 assets/hero/off.jpg
ffmpeg -v error -y -i "$RAW/off.png" -vf "scale=640:-1:flags=lanczos" assets/panel/off.png
cp "$RAW"/icon*.png assets/icon/
