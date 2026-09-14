// Lastshot — puts every new macOS screenshot on the clipboard automatically.
//
// Runs as a menu bar app (no Dock icon). Watches the folder macOS saves
// screenshots to; when a file tagged as a screen capture lands there, it is
// copied to the clipboard as an image plus the file itself.

import AppKit
import UniformTypeIdentifiers
import UserNotifications

struct Screenshot {
    let url: URL
    let created: Date
    let arrived: Date  // ctime: bumped when macOS moves the file in after the thumbnail
}

/// Where macOS currently saves screenshots (⌘⇧5 → Options), falling back to Desktop.
func screenshotFolder() -> URL {
    let domain = "com.apple.screencapture" as CFString
    CFPreferencesAppSynchronize(domain)
    if let location = CFPreferencesCopyAppValue("location" as CFString, domain) as? String {
        let url = URL(fileURLWithPath: (location as NSString).expandingTildeInPath, isDirectory: true)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            return url
        }
    }
    return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
}

func isScreenCapture(_ url: URL) -> Bool {
    getxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) >= 0
}

func screenshots(in folder: URL) -> [Screenshot] {
    let keys: [URLResourceKey] = [.isRegularFileKey, .contentTypeKey, .creationDateKey, .attributeModificationDateKey]
    guard let urls = try? FileManager.default.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
    ) else {
        log("cannot read \(folder.path) — allow access in System Settings → Privacy & Security → Files and Folders")
        return []
    }
    return urls.compactMap { url in
        guard let v = try? url.resourceValues(forKeys: Set(keys)),
              v.isRegularFile == true,
              let type = v.contentType, type.conforms(to: .image) || type.conforms(to: .pdf),
              isScreenCapture(url)
        else { return nil }
        return Screenshot(url: url, created: v.creationDate ?? .distantPast,
                          arrived: v.attributeModificationDate ?? v.creationDate ?? .distantPast)
    }
    .sorted { $0.created > $1.created }
}

func log(_ message: String) {
    FileHandle.standardError.write(Data("\(Date()) \(message)\n".utf8))
}

/// Supplies TIFF only if an app actually asks for it; a Retina TIFF is tens of MB.
final class TIFFProvider: NSObject, NSPasteboardItemDataProvider {
    let data: Data
    init(data: Data) { self.data = data }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        if type == .tiff, let tiff = NSImage(data: data)?.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var pauseItem: NSMenuItem!
    private var source: DispatchSourceFileSystemObject?
    private var watchedFolder: URL?
    private var lastCopied: URL?
    private var pendingScan: DispatchWorkItem?
    private var tiffProvider: TIFFProvider?  // the pasteboard doesn't retain it
    private var paused = UserDefaults.standard.bool(forKey: "paused")

    func applicationDidFinishLaunching(_ note: Notification) {
        setUpMenu()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
        watch()
        // Baseline: don't copy whatever screenshot already exists at launch.
        lastCopied = watchedFolder.flatMap { screenshots(in: $0).first?.url }
        // Pick up changes to the save location.
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.watch() }
    }

    // MARK: Menu

    private func setUpMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Lastshot")
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Copy Latest Screenshot", action: #selector(copyLatest), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Show Latest in Finder", action: #selector(revealLatest), keyEquivalent: ""))
        menu.addItem(.separator())
        pauseItem = NSMenuItem(title: "Copy New Screenshots Automatically", action: #selector(togglePaused), keyEquivalent: "")
        menu.addItem(pauseItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Lastshot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.items.forEach { if $0.action != #selector(NSApplication.terminate(_:)) { $0.target = self } }
        statusItem.menu = menu
        updateMenu()
    }

    private func updateMenu() {
        pauseItem.state = paused ? .off : .on
        statusItem.button?.appearsDisabled = paused
    }

    @objc private func togglePaused() {
        paused.toggle()
        UserDefaults.standard.set(paused, forKey: "paused")
        updateMenu()
    }

    @objc private func copyLatest() {
        guard let shot = screenshots(in: screenshotFolder()).first else { return notify("No screenshots found") }
        if copy(shot.url) { notify("Copied \(shot.url.lastPathComponent)") }
    }

    @objc private func revealLatest() {
        guard let shot = screenshots(in: screenshotFolder()).first else { return notify("No screenshots found") }
        NSWorkspace.shared.activateFileViewerSelecting([shot.url])
    }

    // MARK: Watching

    private func watch() {
        let folder = screenshotFolder()
        guard folder != watchedFolder || source == nil else { return }
        source?.cancel()
        source = nil

        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return log("cannot watch \(folder.path): \(String(cString: strerror(errno)))") }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self, weak src] in
            guard let self, let src else { return }
            if !src.data.isDisjoint(with: [.rename, .delete]) {
                src.cancel(); self.source = nil  // folder itself moved; the timer re-attaches
            } else {
                self.scheduleScan()
            }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
        watchedFolder = folder
        log("watching \(folder.path)")
    }

    /// A save produces a burst of events; wait for it to settle.
    private func scheduleScan() {
        pendingScan?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.scan() }
        pendingScan = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func scan() {
        guard !paused, let folder = watchedFolder,
              let newest = screenshots(in: folder).first,
              newest.url != lastCopied,
              Date().timeIntervalSince(newest.arrived) < 120  // an old screenshot moved back in isn't "new"
        else { return }
        lastCopied = newest.url
        if copy(newest.url) { notify("Screenshot copied — paste with ⌘V") }
    }

    // MARK: Clipboard & notifications

    private func copy(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url) else {
            log("cannot read \(url.path)")
            return false
        }
        let type = UTType(filenameExtension: url.pathExtension) ?? .png
        let item = NSPasteboardItem()
        item.setData(data, forType: NSPasteboard.PasteboardType(type.identifier))
        item.setString(url.absoluteString, forType: .fileURL)
        if type != .tiff {
            let provider = TIFFProvider(data: data)
            item.setDataProvider(provider, forTypes: [.tiff])
            tiffProvider = provider
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let ok = pasteboard.writeObjects([item])
        log(ok ? "copied \(url.path)" : "clipboard write failed for \(url.path)")
        return ok
    }

    private func notify(_ text: String) {
        let content = UNMutableNotificationContent()
        content.title = "Lastshot"
        content.body = text
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
