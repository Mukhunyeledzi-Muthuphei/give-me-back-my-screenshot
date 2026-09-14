# Give Me Back My Screenshot

**The thumbnail vanished. Your screenshot didn't.**

Take a screenshot as usual (⌘⇧3, ⌘⇧4, ⌘⇧5) and it's already on your clipboard. Just press ⌘V.
Missed it? Drag your latest screenshot straight out of the menu bar, any time.

**[Download for Mac](https://github.com/Mukhunyeledzi-Muthuphei/give-me-back-my-screenshot/releases/latest/download/Give-Me-Back-My-Screenshot.zip)** · [Website](https://mukhunyeledzi-muthuphei.github.io/give-me-back-my-screenshot/)

macOS 13+ · Apple silicon & Intel · 400 KB · no network access

## Install

1. Download the zip, unzip it, and drag **Give Me Back My Screenshot** into Applications.
2. Open it. A camera icon appears in the menu bar, and it turns itself on at login.
3. When macOS asks whether it may access your Desktop, click **Allow**.

> **"Apple could not verify…"?** The app isn't notarized (that needs a paid Apple Developer
> account). Go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway**. You only need to do this once.

## Using it

- **Screenshot → ⌘V.** Every new screenshot is copied as an image (for chats and docs) and as a file (for Finder and Mail).
- **Drag the menu bar icon** to drop your latest screenshot anywhere. Dropping on a Finder folder makes a copy.
- **Click the icon** for: Copy Latest Screenshot · Show Latest in Finder · Copy New Screenshots Automatically (untick to pause) · Open at Login · Quit.

## How it works

- macOS tags every screenshot with `kMDItemIsScreenCapture` metadata. The app uses that tag
  instead of file names, so it works in any language and follows your save location (⌘⇧5 → Options).
- With the floating thumbnail on, macOS writes the file only once the thumbnail goes away
  (~5 s, or right away if you swipe it off). That's when it lands on the clipboard.
- The whole app is one Swift file: [`app/GiveMeBackMyScreenshot.swift`](app/GiveMeBackMyScreenshot.swift).

Logs: `log stream --predicate 'subsystem == "com.givemebackmyscreenshot.app"'`

## Build from source

```sh
./install.sh      # builds, installs to ~/Applications, and opens it
./uninstall.sh    # removes it
./build.sh 1.2    # just build build/Give-Me-Back-My-Screenshot.zip
```

Needs the Xcode Command Line Tools (`xcode-select --install`).

It also installs an optional command, `give-me-back-my-screenshot`
(`-n 2` for the one before, `-o` open, `-r` reveal, `-p` path, `-l` list).

## Releasing

Push a version tag. GitHub Actions builds the universal app and publishes a release with the zip attached:

```sh
git tag v1.1 && git push origin v1.1
```

The website's download button always points at the latest release.

## License

MIT
