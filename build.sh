#!/bin/zsh
# Builds a universal (Apple silicon + Intel) "Give Me Back My Screenshot.app"
# and a zip of it, ready to upload to a GitHub release.
#
#   ./build.sh [version]      → build/Give Me Back My Screenshot.app
#                               build/Give-Me-Back-My-Screenshot.zip
set -e
here=${0:A:h}
version=${1:-1.0}
version=${version#v}

name="Give Me Back My Screenshot"
exe=GiveMeBackMyScreenshot
out="$here/build"
app="$out/$name.app"

rm -rf "$out"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target $arch-apple-macos13 \
    "$here/app/$exe.swift" -o "$out/$exe-$arch"
done
lipo -create "$out/$exe-arm64" "$out/$exe-x86_64" -output "$app/Contents/MacOS/$exe"
rm "$out/$exe-arm64" "$out/$exe-x86_64"

cp "$here/app/Info.plist" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $version" "$app/Contents/Info.plist"
cp "$here/give-me-back-my-screenshot" "$app/Contents/Resources/"  # command-line companion

# Ad-hoc signature: required on Apple silicon. Not notarized (that needs a paid
# Apple Developer account), so first launch needs "Open Anyway".
codesign --force --sign - "$app"

ditto -c -k --keepParent "$app" "$out/Give-Me-Back-My-Screenshot.zip"
print "Built $app ($version)"
