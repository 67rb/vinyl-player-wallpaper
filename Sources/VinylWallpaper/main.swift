import AppKit
import WebKit

@objc(VinylApplication) final class VinylApplication: NSApplication {
    @objc func wallpaperSettings(_ sender: Any?) { (delegate as? AppDelegate)?.showSettings(sender) }
    @objc func wallpaperPreview(_ sender: Any?) { (delegate as? AppDelegate)?.showPreview(sender) }
    @objc func wallpaperAbout(_ sender: Any?) { orderFrontStandardAboutPanel(sender) }
    override func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(wallpaperSettings(_:)) || item.action == #selector(wallpaperPreview(_:)) || item.action == #selector(wallpaperAbout(_:)) { return true }
        return super.validateMenuItem(item)
    }
}

final class DesktopWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKScriptMessageHandler, NSWindowDelegate, NSMenuItemValidation, NSUserInterfaceValidations {
    var statusItem: NSStatusItem!
    var windows: [NSWindow] = []
    var scenes: [SceneView] = []
    var screenFrames: [NSRect] = []
    var settings: NSWindow!
    var previewWindow: NSWindow?
    var previewScene: SceneView?
    let ambientSound = AmbientSound()
    var lastSettingsScript = ""
    var lastBroadcast: Data?
    var lastPublishedPlayback: Playback?
    var lastPublishedPreferences = ""
    var lastDiagnostic = Date.distantPast
    var settingsWeb: WKWebView!
    var soundEnabled = UserDefaults.standard.bool(forKey: "sound")
    var soundVolume = UserDefaults.standard.object(forKey: "volume") as? Double ?? 0.15
    var timer: Timer?
    var animationTimer: Timer?
    var playback = Playback()
    let queue = DispatchQueue(label: "Spotify metadata")
    var busy = false
    var denied = false
    var cache: [String: String] = [:]
    var fetching = Set<String>()
    var lastSaved: Data?
    let names = ["Turntable", "Afternoon", "After Hours", "Listening Room", "Soft Rain", "Downpour", "Thunderstorm", "Fireside"]
    let assetNames = ["overhead", "afternoon", "after-hours", "listening-room", "rain-light", "rain-heavy", "rain-storm", "fireside"]
    var root: URL { Bundle.main.resourceURL! }
    var support: URL { FileManager.default.urls(for: .applicationSupportDirectory,in: .userDomainMask)[0].appendingPathComponent("VinylWallpaper") }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildAppMenu()
        if let data = try? Data(contentsOf:support.appendingPathComponent("session.json")), let saved = try? JSONDecoder().decode(Playback.self,from:data) {
            playback = saved
            playback.normalizeHistory()
            playback.playing = false
            playback.status = "Connecting to Spotify"
            func compact(_ track: Track) -> Track {
                if track.art.hasPrefix("data:image/jpeg;") { return track }
                var next=track
                if let comma=track.art.firstIndex(of:","), let data=Data(base64Encoded:String(track.art[track.art.index(after:comma)...])), let art=SceneImages.compactArtwork(data) { next.art=art }
                return next
            }
            playback.track=playback.track.map(compact)
            playback.history=playback.history.map(compact)
        }
        playback.scene = min(assetNames.count - 1, max(0, UserDefaults.standard.integer(forKey: "scene")))
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "opticaldisc", accessibilityDescription: "Vinyl Wallpaper")
        let menu = NSMenu()
        menu.addItem(withTitle: "Wallpapers & Spotify…", action: #selector(showSettings), keyEquivalent: "")
        menu.addItem(withTitle: "Preview Live Wallpaper", action: #selector(showPreview), keyEquivalent: "")
        menu.addItem(withTitle: "Reconnect Spotify", action: #selector(reconnect), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Vinyl Wallpaper", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        statusItem.menu = menu
        buildSettings()
        buildDesktops()
        NotificationCenter.default.addObserver(self, selector: #selector(buildDesktops), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.poll() }
        // Native compositor animation does not need a per-frame callback.
        let animationTimer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.animateWallpapers() }
        RunLoop.main.add(animationTimer, forMode: .common)
        self.animationTimer = animationTimer
        showSettings()
        poll()
    }

    @objc func woke() { reconnect() }
    func animateWallpapers() {
        ambientSound.tick()
        guard Date().timeIntervalSince(lastDiagnostic) >= 10, let scene=scenes.first else { return }
        lastDiagnostic=Date()
        var report=scene.report()
        report["desktopWebViews"]=0
        report["settingsLoaded"]=settingsWeb != nil
        if let data=try? JSONSerialization.data(withJSONObject:report,options:.sortedKeys) { try? data.write(to:support.appendingPathComponent("renderer.json"),options:.atomic) }
    }
    func buildAppMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(title: "Vinyl Wallpaper"); appMenu.autoenablesItems = true; appItem.submenu = appMenu
        let aboutItem = appMenu.addItem(withTitle:"About Vinyl Wallpaper",action:#selector(VinylApplication.wallpaperAbout(_:)),keyEquivalent:""); aboutItem.target = nil
        let settingsItem = appMenu.addItem(withTitle:"Wallpapers & Spotify…",action:#selector(VinylApplication.wallpaperSettings(_:)),keyEquivalent:","); settingsItem.target = nil
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle:"Hide Vinyl Wallpaper",action:#selector(NSApplication.hide(_:)),keyEquivalent:"h")
        let hideOthers = appMenu.addItem(withTitle:"Hide Others",action:#selector(NSApplication.hideOtherApplications(_:)),keyEquivalent:"h"); hideOthers.keyEquivalentModifierMask = [.command,.option]
        appMenu.addItem(withTitle:"Show All",action:#selector(NSApplication.unhideAllApplications(_:)),keyEquivalent:"")
        appMenu.addItem(.separator())
        let quitItem = appMenu.addItem(withTitle:"Quit Vinyl Wallpaper",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q"); quitItem.target = nil
        let windowItem = NSMenuItem(); main.addItem(windowItem)
        let windowMenu = NSMenu(title:"Window"); windowMenu.autoenablesItems = true; windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle:"Minimize",action:#selector(NSWindow.performMiniaturize(_:)),keyEquivalent:"m")
        windowMenu.addItem(withTitle:"Close",action:#selector(NSWindow.performClose(_:)),keyEquivalent:"w")
        let previewItem = windowMenu.addItem(withTitle:"Live Wallpaper Preview",action:#selector(VinylApplication.wallpaperPreview(_:)),keyEquivalent:"p"); previewItem.target = nil
        NSApp.mainMenu = main; NSApp.windowsMenu = windowMenu
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSettings(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func updatePreviewActivity() {
        let settingsVisible = settings?.isVisible == true && settings?.occlusionState.contains(.visible) == true
        settingsWeb?.evaluateJavaScript("window.settings?.setActive(\(settingsVisible))",completionHandler:nil)
        let previewVisible = previewWindow?.isVisible == true && previewWindow?.occlusionState.contains(.visible) == true
        previewScene?.setActive(previewVisible)
    }
    func windowDidChangeOcclusionState(_ notification: Notification) { updatePreviewActivity() }
    func windowDidMiniaturize(_ notification: Notification) { updatePreviewActivity() }
    func windowDidDeminiaturize(_ notification: Notification) { updatePreviewActivity() }
    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === settings {
            settingsWeb?.stopLoading()
            settingsWeb?.configuration.userContentController.removeScriptMessageHandler(forName:"app")
            settingsWeb?.navigationDelegate=nil
            settings.contentView=nil;settingsWeb=nil;settings=nil;lastSettingsScript=""
        }
        if notification.object as? NSWindow === previewWindow {
            previewScene?.stop();previewWindow?.contentView=nil;previewScene=nil;previewWindow=nil
        }
    }
    @objc func showAbout(_ sender: Any?) { NSApp.orderFrontStandardAboutPanel(sender) }
    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { true }
    @objc func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool { true }
    @objc func quit(_ sender: Any? = nil) { NSApp.terminate(nil) }
    @objc func showSettings(_ sender: Any? = nil) { if settings == nil { buildSettings() }; settings.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); updatePreviewActivity() }
    @objc func showPreview(_ sender: Any? = nil) {
        if previewWindow == nil {
            let window = NSWindow(contentRect:NSRect(x:0,y:0,width:1000,height:630),styleMask:[.titled,.closable,.resizable,.miniaturizable],backing:.buffered,defer:false)
            window.title="Live Wallpaper Preview";window.delegate=self;window.isReleasedWhenClosed=false
            window.backgroundColor = .black
            let scene=SceneView(frame:NSRect(x:0,y:0,width:1000,height:630));scene.autoresizingMask=[.width,.height]
            window.contentView=scene;scene.update(playback);window.center()
            previewWindow=window;previewScene=scene
        }
        previewWindow?.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true);updatePreviewActivity()
    }
    @objc func reconnect(_ sender: Any? = nil) { denied = false; poll() }
    @objc func openSpotify() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
        reconnect()
    }
    @objc func privacy() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!) }
    @objc func clearHistory() { playback.history = []; broadcast() }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.webView === settingsWeb, let body = message.body as? [String:Any], let action = body["action"] as? String else { return }
        switch action {
        case "scene":
            guard let value = body["value"] as? Int, assetNames.indices.contains(value) else { return }
            playback.scene = value
            UserDefaults.standard.set(value,forKey:"scene")
        case "enabled":
            guard let value = body["value"] as? Bool else { return }
            UserDefaults.standard.set(!value,forKey:"disabled")
            buildDesktops()
        case "sound":
            guard let value = body["value"] as? Bool else { return }
            soundEnabled = value
            UserDefaults.standard.set(value,forKey:"sound")
        case "volume":
            guard let value = body["value"] as? Double, value.isFinite else { return }
            soundVolume = min(0.5,max(0,value))
            UserDefaults.standard.set(soundVolume,forKey:"volume")
        case "spotify": openSpotify()
        case "reconnect": reconnect()
        case "privacy": privacy()
        case "preview": showPreview()
        case "clear": playback.history = []
        default: return
        }
        broadcast()
    }
    func buildSettings() {
        settings = NSWindow(contentRect:NSRect(x:0,y:0,width:1100,height:850),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        settings.title = "Vinyl — Your listening room"
        settings.delegate = self
        settings.titlebarAppearsTransparent = true
        settings.backgroundColor = NSColor(srgbRed:0.085,green:0.09,blue:0.08,alpha:1)
        settings.minSize = NSSize(width:820,height:700)
        settings.isReleasedWhenClosed = false
        settings.center()
        let config = WKWebViewConfiguration()
        config.userContentController.add(self,name:"app")
        settingsWeb = WKWebView(frame:NSRect(x:0,y:0,width:1100,height:850),configuration:config)
        settingsWeb.setValue(false,forKey:"drawsBackground")
        settingsWeb.autoresizingMask = [.width,.height]
        settingsWeb.navigationDelegate = self
        settings.contentView = settingsWeb
        settingsWeb.loadFileURL(root.appendingPathComponent("settings.html"),allowingReadAccessTo:root)
    }

    @objc func buildDesktops() {
        let disabled=UserDefaults.standard.bool(forKey:"disabled")
        let screens=NSScreen.screens
        let frames=screens.map { $0.frame }
        if !disabled, frames == screenFrames, !windows.isEmpty { return }
        for scene in scenes { scene.stop() }
        for window in windows { window.contentView=nil;window.orderOut(nil);window.close() }
        scenes.removeAll();windows.removeAll();screenFrames=[]
        guard !disabled else { ambientSound.update(scene:playback.scene,enabled:false,volume:soundVolume);return }
        screenFrames=frames
        for screen in screens {
            let window=DesktopWindow(contentRect:screen.frame,styleMask:.borderless,backing:.buffered,defer:false)
            window.isReleasedWhenClosed=false
            window.level=NSWindow.Level(rawValue:Int(CGWindowLevelForKey(.desktopWindow))+1)
            window.collectionBehavior=[.canJoinAllSpaces,.stationary,.ignoresCycle]
            window.canHide=false;window.isExcludedFromWindowsMenu=true;window.ignoresMouseEvents=true;window.backgroundColor = .black
            let scene=SceneView(frame:NSRect(origin:.zero,size:screen.frame.size));scene.autoresizingMask=[.width,.height]
            window.contentView=scene;scene.update(playback);window.orderBack(nil)
            windows.append(window);scenes.append(scene)
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { lastSettingsScript="";broadcast();updatePreviewActivity() }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // Only the optional settings window uses WebKit. Desktop layers stay intact.
        if webView === settingsWeb, settings?.isVisible == true { lastSettingsScript="";webView.reload() }
    }
    func broadcast() {
        ambientSound.update(scene:playback.scene,enabled:soundEnabled && !windows.isEmpty,volume:soundVolume)
        let prefs="{enabled:\(!UserDefaults.standard.bool(forKey:"disabled")),sound:\(soundEnabled),volume:\(soundVolume)}"
        guard playback != lastPublishedPlayback || prefs != lastPublishedPreferences || (settingsWeb != nil && lastSettingsScript.isEmpty) else { return }
        guard let data=try? JSONEncoder().encode(playback),let json=String(data:data,encoding:.utf8) else { return }
        lastPublishedPlayback=playback;lastPublishedPreferences=prefs
        let script="window.settings?.update(\(json),\(prefs))"
        if settingsWeb != nil, script != lastSettingsScript { lastSettingsScript=script;settingsWeb.evaluateJavaScript(script,completionHandler:nil) }
        if data != lastBroadcast { for scene in scenes { scene.update(playback) };previewScene?.update(playback);lastBroadcast=data }
        let dir=support
        try? FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        if data != lastSaved { try? data.write(to:dir.appendingPathComponent("session.json"),options:.atomic);lastSaved=data }
        var diagnostic=playback
        if var t=diagnostic.track { t.art=t.art.isEmpty ? "" : "cached artwork";diagnostic.track=t }
        diagnostic.history=diagnostic.history.map { var t=$0;t.art=t.art.isEmpty ? "" : "cached artwork";return t }
        if let d=try? JSONEncoder().encode(diagnostic) { try? d.write(to:dir.appendingPathComponent("status.json"),options:.atomic) }
    }
    func poll() {
        guard !busy && !denied else { return }
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty else {
            playback.playing = false; playback.status = "Spotify is closed"; broadcast(); return
        }
        busy = true
        queue.async { [weak self] in
            let source = """
            with timeout of 5 seconds
                tell application id "com.spotify.client"
                    set t to current track
                    return {id of t, name of t, artist of t, artwork url of t, (player state as string)}
                end tell
            end timeout
            """
            let (values,errorCode): ([String],Int?) = autoreleasepool {
                var error: NSDictionary?
                let result=NSAppleScript(source:source)?.executeAndReturnError(&error)
                return ((1...5).map { result?.atIndex($0)?.stringValue ?? "" },error?[NSAppleScript.errorNumber] as? Int)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                if let code = errorCode {
                    self.denied = code == -1743
                    self.playback.playing = false
                    self.playback.status = self.denied ? "Allow Spotify in System Settings → Privacy & Security → Automation, then Reconnect." : "Waiting for Spotify to provide a song (\(code))"
                    self.broadcast(); return
                }
                guard !values[0].isEmpty else { self.playback.playing = false; self.playback.status = "Waiting for a Spotify song"; self.broadcast(); return }
                guard values[0].hasPrefix("spotify:track:"), values[1].localizedCaseInsensitiveCompare("Up next") != .orderedSame else {
                    self.playback.playing = values[4] == "playing"
                    self.playback.status = "Connected · Waiting for Spotify track details"
                    self.broadcast(); return
                }
                let art = self.cache[values[3]] ?? (self.playback.track?.id == values[0] ? self.playback.track?.art ?? "" : "")
                let track = Track(id: values[0], name: values[1], artist: values[2], art: art)
                self.playback.receive(track, playing: values[4] == "playing")
                self.broadcast()
                self.fetchArt(values[3], trackID: values[0])
            }
        }
    }
    func fetchArt(_ source: String, trackID: String) {
        guard cache[source] == nil, !fetching.contains(source), let url = URL(string: source), url.scheme == "https" else { return }
        fetching.insert(source)
        URLSession.shared.dataTask(with:url) { [weak self] data,response,error in
            let encoded: String? = autoreleasepool {
                guard error == nil,let data,data.count < 12_000_000,let response=response as? HTTPURLResponse,response.statusCode == 200 else { return nil }
                return SceneImages.compactArtwork(data)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.fetching.remove(source)
                guard let encoded else { return }
                if self.cache.count >= 12 { self.cache.removeAll() }
                self.cache[source]=encoded
                if self.playback.track?.id == trackID { self.playback.track?.art=encoded }
                for i in self.playback.history.indices where self.playback.history[i].id == trackID { self.playback.history[i].art=encoded }
                self.broadcast()
            }
        }.resume()
    }
}

let app = VinylApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
