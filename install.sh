#!/bin/zsh
# Builds the app from source, installs it to ~/Applications, and opens it.
# (Most people should just download the zip from GitHub Releases instead.)
set -e
here=${0:A:h}
name="Give Me Back My Screenshot"
app="$HOME/Applications/$name.app"

"$here/build.sh"

osascript -e "quit app \"$name\"" 2>/dev/null || true
mkdir -p "${app:h}" "$HOME/.local/bin"
rm -rf "$app"
cp -R "$here/build/$name.app" "$app"
ln -sf "$app/Contents/Resources/give-me-back-my-screenshot" "$HOME/.local/bin/give-me-back-my-screenshot"

open "$app"
print "Installed to $app — look for the camera icon in your menu bar."
