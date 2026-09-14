#!/bin/zsh
# Quits Give Me Back My Screenshot and removes it.
name="Give Me Back My Screenshot"
osascript -e "quit app \"$name\"" 2>/dev/null
# Older versions started via a LaunchAgent.
launchctl bootout "gui/$UID/com.givemebackmyscreenshot.app" 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/com.givemebackmyscreenshot.app.plist" "$HOME/.local/bin/give-me-back-my-screenshot"
rm -rf "$HOME/Applications/$name.app" "/Applications/$name.app"
print "Uninstalled. Screenshots are no longer copied automatically."
