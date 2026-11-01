#!/bin/zsh
# Builds XDRBoost.app next to this script.
#   ./build.sh           build for this Mac
#   ./build.sh install   build and copy to ~/Applications (needed for "launch at login")
#   ./build.sh release   universal build zipped into dist/
set -e
cd "$(dirname "$0")"
VERSION=0.1.0
APP=XDRBoost.app
# Build and sign in a scratch folder, then copy: a synced folder (iCloud Desktop) adds File Provider attributes
# while codesign runs, and codesign refuses a bundle with those.
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
B="$STAGE/$APP"
mkdir -p "$B/Contents/MacOS"
# An explicit deployment target: swiftc otherwise targets the SDK's OS version, which Launch Services refuses
# (open, Login Items) on a Mac running an older point release.
FLAGS=(-O -swift-version 5 -framework AppKit -framework Metal -framework MetalKit -framework ServiceManagement)
if [[ "$1" == "release" ]]; then
  for arch in arm64 x86_64; do
    swiftc $FLAGS -target $arch-apple-macos13.0 -o "$STAGE/XDRBoost-$arch" Sources/*.swift
  done
  lipo -create -output "$B/Contents/MacOS/XDRBoost" "$STAGE/XDRBoost-arm64" "$STAGE/XDRBoost-x86_64"
else
  swiftc $FLAGS -target "$(uname -m)-apple-macos13.0" -o "$B/Contents/MacOS/XDRBoost" Sources/*.swift
fi
cat > "$B/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>XDR Boost</string>
  <key>CFBundleIdentifier</key><string>local.xdr-boost</string>
  <key>CFBundleExecutable</key><string>XDRBoost</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
xattr -cr "$B"
codesign --force -s - "$B" || echo "warning: codesign failed"
rm -rf "$APP"
ditto "$B" "$APP"
echo "built $PWD/$APP"

if [[ "$1" == "install" ]]; then
  mkdir -p ~/Applications
  pkill -f "XDRBoost.app/Contents/MacOS/XDRBoost" || true
  rm -rf ~/Applications/XDRBoost.app
  ditto "$B" ~/Applications/XDRBoost.app
  echo "installed ~/Applications/XDRBoost.app"
fi

if [[ "$1" == "release" ]]; then
  mkdir -p dist
  rm -f "dist/XDRBoost-$VERSION.zip"
  ditto -c -k --keepParent "$B" "dist/XDRBoost-$VERSION.zip"
  echo "packed $PWD/dist/XDRBoost-$VERSION.zip"
fi
