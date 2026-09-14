#!/bin/zsh
# Stops Give Me Back My Screenshot and removes it.
label=com.givemebackmyscreenshot.app
launchctl bootout "gui/$UID/$label" 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/$label.plist" "$HOME/.local/bin/give-me-back-my-screenshot"
rm -rf "$HOME/Applications/Give Me Back My Screenshot.app"
print "Uninstalled. Screenshots are no longer copied automatically."
