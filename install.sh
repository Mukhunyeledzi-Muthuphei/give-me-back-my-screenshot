#!/bin/zsh
# Builds Lastshot.app, installs it to ~/Applications, and starts it at login.
# From then on every new screenshot is copied to the clipboard automatically.
set -e
here=${0:A:h}

label=com.lastshot.app
app=$HOME/Applications/Lastshot.app
agent=$HOME/Library/LaunchAgents/$label.plist
log=$HOME/Library/Logs/Lastshot.log

print "Building…"
build=$here/build/Lastshot.app
rm -rf "$build"
mkdir -p "$build/Contents/MacOS"
mkdir -p "$build/Contents/Resources"
cp "$here/app/Info.plist" "$build/Contents/Info.plist"
cp "$here/lastshot" "$build/Contents/Resources/lastshot"  # command-line companion
swiftc -O -swift-version 5 "$here/app/Lastshot.swift" -o "$build/Contents/MacOS/Lastshot"
codesign --force --sign - "$build"

launchctl bootout "gui/$UID/$label" 2>/dev/null || true
mkdir -p "${app:h}" "${agent:h}" "$HOME/.local/bin"
rm -rf "$app"
cp -R "$build" "$app"

ln -sf "$app/Contents/Resources/lastshot" "$HOME/.local/bin/lastshot"

cat > "$agent" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array><string>$app/Contents/MacOS/Lastshot</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ProcessType</key><string>Interactive</string>
  <key>StandardErrorPath</key><string>$log</string>
</dict>
</plist>
EOF
launchctl bootstrap "gui/$UID" "$agent"

print "
Installed — look for the camera icon in your menu bar.
If macOS asks whether Lastshot may access your Desktop, click Allow.
From now on, every new screenshot is on your clipboard: just press ⌘V.

Uninstall: $here/uninstall.sh"
