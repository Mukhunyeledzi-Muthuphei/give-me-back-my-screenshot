#!/bin/zsh
# Builds "Give Me Back My Screenshot.app", installs it to ~/Applications, and
# starts it at login. From then on every new screenshot is copied to the
# clipboard automatically.
set -e
here=${0:A:h}

name="Give Me Back My Screenshot"
exe=GiveMeBackMyScreenshot
label=com.givemebackmyscreenshot.app
app="$HOME/Applications/$name.app"
agent="$HOME/Library/LaunchAgents/$label.plist"
log="$HOME/Library/Logs/$exe.log"

print "Building…"
build="$here/build/$name.app"
rm -rf "$build"
mkdir -p "$build/Contents/MacOS" "$build/Contents/Resources"
cp "$here/app/Info.plist" "$build/Contents/Info.plist"
cp "$here/give-me-back-my-screenshot" "$build/Contents/Resources/give-me-back-my-screenshot"  # command-line companion
swiftc -O -swift-version 5 "$here/app/$exe.swift" -o "$build/Contents/MacOS/$exe"
codesign --force --sign - "$build"

launchctl bootout "gui/$UID/$label" 2>/dev/null || true
mkdir -p "${app:h}" "${agent:h}" "$HOME/.local/bin"
rm -rf "$app"
cp -R "$build" "$app"

ln -sf "$app/Contents/Resources/give-me-back-my-screenshot" "$HOME/.local/bin/give-me-back-my-screenshot"

cat > "$agent" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array><string>$app/Contents/MacOS/$exe</string></array>
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
If macOS asks whether $name may access your Desktop, click Allow.
From now on, every new screenshot is on your clipboard: just press ⌘V.

Uninstall: $here/uninstall.sh"
