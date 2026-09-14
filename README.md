# Give Me Back My Screenshot

Take a screenshot as usual (⌘⇧3, ⌘⇧4, ⌘⇧5) and it's **already on your clipboard**. Just press ⌘V.
The file is still saved as normal.

## Install

```sh
./install.sh
```

A camera icon appears in the menu bar. The first time, macOS asks whether **Give Me Back My Screenshot** may access
your Desktop (or wherever you save screenshots). Click **Allow**. It starts automatically at login.

**Drag the menu bar icon** to drop your latest screenshot anywhere: Slack, Mail, a browser upload
box, a Finder folder (it copies, never moves). It works like the floating thumbnail's drag, but any time.

**Click the icon** for:

- **Copy Latest Screenshot**: get it back after you've copied something else
- **Show Latest in Finder**
- **Copy New Screenshots Automatically**: untick to pause
- **Quit Give Me Back My Screenshot**: stays quit until next login

Uninstall with `./uninstall.sh`.

## How it works

- macOS tags every screenshot with `kMDItemIsScreenCapture` metadata. The app uses that tag
  instead of file names, so it works in any language and follows your save location
  (⌘⇧5 → Options), even if you change it.
- With the floating thumbnail on, macOS writes the file only once the thumbnail goes away
  (~5 s, or right away if you swipe it off). That's when it lands on the clipboard.
- The clipboard gets the image **and** the file. Chats and documents paste the picture; Finder
  and Mail paste the file.
- It's a small native app (`app/GiveMeBackMyScreenshot.swift`) because macOS doesn't let background shell
  scripts read the Desktop. The app gets its own privacy permission instead.

Log: `~/Library/Logs/GiveMeBackMyScreenshot.log`

## Command line (optional)

`install.sh` also puts `give-me-back-my-screenshot` in `~/.local/bin`:

```
give-me-back-my-screenshot          copy newest screenshot to clipboard
give-me-back-my-screenshot -n 2     the one before that
give-me-back-my-screenshot -o / -r  open it / reveal it in Finder
give-me-back-my-screenshot -p       print its path
give-me-back-my-screenshot -l [N]   list the N newest
```
