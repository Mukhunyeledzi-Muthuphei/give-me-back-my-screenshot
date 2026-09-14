#!/bin/zsh
# Stops Lastshot and removes it.
label=com.lastshot.app
launchctl bootout "gui/$UID/$label" 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/$label.plist" "$HOME/.local/bin/lastshot"
rm -rf "$HOME/Applications/Lastshot.app" "$HOME/Library/Application Support/lastshot"
print "Uninstalled. Screenshots are no longer copied automatically."
