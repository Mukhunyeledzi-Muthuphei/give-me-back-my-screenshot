// Give Me Back My Screenshot — puts every new macOS screenshot on the clipboard automatically.
//
// Runs as a menu bar app (no Dock icon). Watches the folder macOS saves
// screenshots to; when a file tagged as a screen capture lands there, it is
// copied to the clipboard as an image plus the file itself.

import AppKit
import os
import ServiceManagement
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

private let logger = Logger(subsystem: "com.givemebackmyscreenshot.app", category: "app")

/// View with: log stream --predicate 'subsystem == "com.givemebackmyscreenshot.app"'
func log(_ message: String) {
    logger.log("\(message, privacy: .public)")
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

/// Clipboard/drag contents for a screenshot: the image data plus the file itself,
/// so chats and documents get the picture and Finder/Mail get the file.
func pasteboardItem(for url: URL, data: Data, tiffProvider: TIFFProvider?) -> NSPasteboardItem {
    let type = UTType(filenameExtension: url.pathExtension) ?? .png
    let item = NSPasteboardItem()
    item.setString(url.absoluteString, forType: .fileURL)
    item.setData(data, forType: NSPasteboard.PasteboardType(type.identifier))
    if type != .tiff, let tiffProvider {
        item.setDataProvider(tiffProvider, forTypes: [.tiff])
    }
    return item
}

/// Sits over the menu bar icon: a click opens the menu, a drag picks up the
/// latest screenshot — the floating thumbnail's drag, but available any time.
final class StatusItemDragView: NSView, NSDraggingSource {
    var latestScreenshot: () -> URL? = { nil }
    var openMenu: () -> Void = {}

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let start = event.locationInWindow
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { return openMenu() }
            let p = next.locationInWindow
            if hypot(p.x - start.x, p.y - start.y) > 3 { return beginDrag(with: event) }
        }
    }

    override func rightMouseDown(with event: NSEvent) { openMenu() }

    private func beginDrag(with event: NSEvent) {
        guard let url = latestScreenshot(), let data = try? Data(contentsOf: url) else { return NSSound.beep() }
        let item = NSDraggingItem(pasteboardWriter: pasteboardItem(for: url, data: data, tiffProvider: nil))
        let preview = thumbnail(of: data, maxSide: 160)
        let p = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(NSRect(x: p.x - preview.size.width / 2, y: p.y - preview.size.height / 2,
                                     width: preview.size.width, height: preview.size.height),
                              contents: preview)
        beginDraggingSession(with: [item], event: event, source: self).animatesToStartingPositionsOnCancelOrFail = true
    }

    // Copy, never move: dropping on a Finder folder must leave the original in place.
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    private func thumbnail(of data: Data, maxSide: CGFloat) -> NSImage {
        guard let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 else {
            return NSImage(systemSymbolName: "photo", accessibilityDescription: nil)!
        }
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        return NSImage(size: size, flipped: false) { rect in
            image.draw(in: rect)
            NSColor.white.withAlphaComponent(0.8).setStroke()
            NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5)).stroke()
            return true
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var pauseItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var source: DispatchSourceFileSystemObject?
    private var watchedFolder: URL?
    private var watching = false
    private var lastCopied: URL?
    private var pendingScan: DispatchWorkItem?
    private var tiffProvider: TIFFProvider?  // the pasteboard doesn't retain it
    private var paused = UserDefaults.standard.bool(forKey: "paused")

    func applicationDidFinishLaunching(_ note: Notification) {
        guard isInApplicationsFolder() else { return askToMoveToApplications() }
        setUpMenu()
        if !UserDefaults.standard.bool(forKey: "welcomed") {
            UserDefaults.standard.set(true, forKey: "welcomed")
            try? SMAppService.mainApp.register()
            updateMenu()
            showWelcome()
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
        watch()
        // Pick up changes to the save location.
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.watch() }
    }

    // MARK: First launch

    /// Launched from Downloads, macOS runs the app from a temporary read-only copy
    /// (App Translocation), which would break Open at Login.
    private func isInApplicationsFolder() -> Bool {
        let path = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix("/Applications/") || path.hasPrefix(home + "/Applications/")
    }

    private func askToMoveToApplications() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Move to Applications first"
        alert.informativeText = "Drag Give Me Back My Screenshot into your Applications folder, then open it from there."
        alert.addButton(withTitle: "Open Applications Folder")
        alert.addButton(withTitle: "Quit")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
        }
        NSApp.terminate(nil)
    }

    private func showWelcome() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Give Me Back My Screenshot is running"
        alert.informativeText = """
            It lives in your menu bar (the camera icon). Every screenshot you take is now \
            on your clipboard, so just press ⌘V. Drag the icon to drop your latest screenshot anywhere.

            Next, macOS will ask to let it access your Desktop so it can see new screenshots. Click Allow.
            """
        alert.addButton(withTitle: "Got It")
        alert.runModal()
    }

    // MARK: Menu

    private func setUpMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Give Me Back My Screenshot")
        statusItem.button?.toolTip = "Click for menu · Drag to drop your latest screenshot anywhere"
        menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Copy Latest Screenshot", action: #selector(copyLatest), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Show Latest in Finder", action: #selector(revealLatest), keyEquivalent: ""))
        menu.addItem(.separator())
        pauseItem = NSMenuItem(title: "Copy New Screenshots Automatically", action: #selector(togglePaused), keyEquivalent: "")
        menu.addItem(pauseItem)
        loginItem = NSMenuItem(title: "Open at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Give Me Back My Screenshot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.items.forEach { if $0.action != #selector(NSApplication.terminate(_:)) { $0.target = self } }

        // The menu is attached only while opening it; otherwise the button would
        // swallow mouse-down and the drag view could never start a drag.
        if let button = statusItem.button {
            let dragView = StatusItemDragView(frame: button.bounds)
            dragView.autoresizingMask = [.width, .height]
            dragView.latestScreenshot = { screenshots(in: screenshotFolder()).first?.url }
            dragView.openMenu = { [weak self] in
                guard let self else { return }
                self.statusItem.menu = self.menu
                self.statusItem.button?.performClick(nil)
                self.statusItem.menu = nil
            }
            button.addSubview(dragView)
        }
        updateMenu()
    }

    private func updateMenu() {
        pauseItem.state = paused ? .off : .on
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        statusItem.button?.appearsDisabled = paused
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            log("login item: \(error.localizedDescription)")
        }
        updateMenu()
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
        guard !watching, folder != watchedFolder || source == nil else { return }
        source?.cancel()
        source = nil
        watching = true

        // The first open of a protected folder blocks until the user answers the
        // privacy prompt, so keep it off the main thread.
        DispatchQueue.global(qos: .userInitiated).async {
            let fd = open(folder.path, O_EVTONLY)
            let error = errno
            // Baseline: don't copy whatever screenshot is already there.
            let newest = fd >= 0 ? screenshots(in: folder).first?.url : nil
            DispatchQueue.main.async {
                self.watching = false
                guard fd >= 0 else { return log("cannot watch \(folder.path): \(String(cString: strerror(error)))") }
                if self.lastCopied == nil || folder != self.watchedFolder { self.lastCopied = newest }
                self.attach(fd: fd, folder: folder)
            }
        }
    }

    private func attach(fd: Int32, folder: URL) {
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
        let provider = TIFFProvider(data: data)
        tiffProvider = provider
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let ok = pasteboard.writeObjects([pasteboardItem(for: url, data: data, tiffProvider: provider)])
        log(ok ? "copied \(url.path)" : "clipboard write failed for \(url.path)")
        return ok
    }

    private func notify(_ text: String) {
        let content = UNMutableNotificationContent()
        content.title = "Give Me Back My Screenshot"
        content.body = text
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
