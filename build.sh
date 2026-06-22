#!/bin/bash
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD="$DIR/build"
APP="$BUILD/NoSleep.app/Contents"

rm -rf "$BUILD"
mkdir -p "$APP/MacOS"
mkdir -p "$APP/Resources"

echo "Compiling with Swift Package Manager..."
cd "$DIR"
swift build -c release 2>&1

# Copy the built binary into the .app bundle
cp "$(swift build -c release --show-bin-path)/NoSleep" "$APP/MacOS/NoSleep"

# Copy Info.plist
cp "$DIR/Info.plist" "$APP/Info.plist"

# Ad-hoc codesign
codesign --force --deep --sign - "$BUILD/NoSleep.app"

echo ""
echo "Built: $BUILD/NoSleep.app"
echo "Install: cp -r $BUILD/NoSleep.app /Applications/"
