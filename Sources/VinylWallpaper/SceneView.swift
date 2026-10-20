import AppKit
import AVFoundation
import ImageIO
import QuartzCore
import UniformTypeIdentifiers

// Only the selected room and a small, shared set of artwork are decoded.
final class SceneImages {
    static let shared = SceneImages()
    private let cache = NSCache<NSString, CGImage>()
    init() { cache.totalCostLimit = 24 * 1024 * 1024; cache.countLimit = 14 }
    func image(_ source: String, maxSize: Int = 1600) -> CGImage? {
        guard !source.isEmpty else { return nil }
        let key = "\(maxSize):\(source)" as NSString
        if let image = cache.object(forKey: key) { return image }
        let input: CGImageSource?
        if source.hasPrefix("data:"), let comma = source.firstIndex(of: ","), let data = Data(base64Encoded: String(source[source.index(after: comma)...])) {
            input = CGImageSourceCreateWithData(data as CFData, nil)
        } else {
            let url = Bundle.main.resourceURL!.appendingPathComponent("assets/\(source)")
            input = CGImageSourceCreateWithURL(url as CFURL, nil)
        }
        guard let input, let image = CGImageSourceCreateThumbnailAtIndex(input, 0, [kCGImageSourceCreateThumbnailFromImageAlways:true, kCGImageSourceThumbnailMaxPixelSize:maxSize, kCGImageSourceCreateThumbnailWithTransform:true, kCGImageSourceShouldCacheImmediately:true] as CFDictionary) else { return nil }
        cache.setObject(image, forKey:key, cost:image.bytesPerRow * image.height)
        return image
    }
    static func compactArtwork(_ data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways:true, kCGImageSourceThumbnailMaxPixelSize:512, kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality:0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return "data:image/jpeg;base64," + (output as Data).base64EncodedString()
    }
}

// No WebKit process, JavaScript frame bridge, or page reload on the desktop.
final class SceneView: NSView {
    override var isFlipped: Bool { true }
    private let world = CALayer(), room = CALayer(), windowPhoto = CALayer(), sleeve = CALayer(), recordPlane = CALayer(), record = CALayer(), label = CALayer(), arm = CALayer(), history = CALayer()
    private let windowImage = CALayer(), windowShade = CALayer()
    private let spindle = CALayer()
    private let sleeveShade = CALayer(), labelShade = CALayer()
    let rain = RainView(frame:.zero)
    private let fireLayer = AVPlayerLayer()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var sceneIndex = -1
    private var artKey = ""
    private var historyKey: [Track]?
    private var playing = false, active = true
    private var preferences = VisualPreferences()
    private var started = Date()

    override init(frame: NSRect) {
        super.init(frame:frame)
        setAccessibilityElement(true);setAccessibilityRole(.group)
        wantsLayer = true
        layer?.backgroundColor = NSColor(srgbRed:0.13,green:0.09,blue:0.06,alpha:1).cgColor
        layer?.masksToBounds = true
        layer?.isGeometryFlipped = true
        // The NSView root already supplies the top-left coordinate system.
        world.isGeometryFlipped = false
        layer?.addSublayer(world)
        for child in [room,windowPhoto,fireLayer,history,sleeve,recordPlane,arm] { world.addSublayer(child) }
        windowPhoto.addSublayer(windowImage);windowPhoto.addSublayer(windowShade)
        windowPhoto.masksToBounds=true;windowShade.backgroundColor=NSColor.black.cgColor
        recordPlane.addSublayer(record); record.addSublayer(label)
        sleeveShade.backgroundColor=NSColor.black.cgColor;labelShade.backgroundColor=NSColor.black.cgColor
        sleeve.addSublayer(sleeveShade);label.addSublayer(labelShade)
        recordPlane.addSublayer(spindle);spindle.backgroundColor=NSColor(srgbRed:0.75,green:0.68,blue:0.52,alpha:1).cgColor
        sleeve.masksToBounds = true; sleeve.borderWidth = 2; sleeve.borderColor = NSColor(srgbRed:0.85,green:0.80,blue:0.71,alpha:1).cgColor
        sleeve.backgroundColor = NSColor(srgbRed:0.18,green:0.20,blue:0.16,alpha:1).cgColor
        label.masksToBounds = true; label.backgroundColor = NSColor(srgbRed:0.77,green:0.70,blue:0.58,alpha:1).cgColor
        record.contents = SceneImages.shared.image("vinyl-record.png", maxSize:700)
        fireLayer.videoGravity = .resizeAspectFill
        addSubview(rain)
        rain.autoresizingMask = [.width,.height]
    }
    required init?(coder:NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        guard RoomCatalog.scenes.indices.contains(sceneIndex) else { return }
        let scene = RoomCatalog.scenes[sceneIndex]
        let scale = max(bounds.width / scene.w, bounds.height / scene.h)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        world.bounds = CGRect(x:0,y:0,width:scene.w,height:scene.h)
        world.position = CGPoint(x:bounds.midX,y:bounds.midY)
        world.setAffineTransform(CGAffineTransform(scaleX:scale,y:scale))
        rain.frame = bounds
        CATransaction.commit()
    }
    private func rect(_ layer: CALayer, _ values: [Double]) {
        layer.anchorPoint = .zero; layer.position = CGPoint(x:values[0],y:values[1]); layer.bounds = CGRect(x:0,y:0,width:values[2],height:values[3]); layer.transform = CATransform3DIdentity
    }
    private func project(_ layer: CALayer, _ quad: [[Double]]) {
        let x0=quad[0][0],y0=quad[0][1],x1=quad[1][0],y1=quad[1][1],x2=quad[2][0],y2=quad[2][1],x3=quad[3][0],y3=quad[3][1]
        let dx1=x1-x2,dx2=x3-x2,dx3=x0-x1+x2-x3,dy1=y1-y2,dy2=y3-y2,dy3=y0-y1+y2-y3
        let denominator=dx1*dy2-dx2*dy1,g=(dx3*dy2-dx2*dy3)/denominator,h=(dx1*dy3-dx3*dy1)/denominator
        rect(layer,[0,0,400,400])
        var t=CATransform3DIdentity
        t.m11=(x1-x0+g*x1)/400; t.m12=(y1-y0+g*y1)/400; t.m14=g/400
        t.m21=(x3-x0+h*x3)/400; t.m22=(y3-y0+h*y3)/400; t.m24=h/400
        t.m41=x0; t.m42=y0; layer.transform=t
    }
    func update(_ state: Playback) {
        guard RoomCatalog.scenes.indices.contains(state.scene) else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if state.scene != sceneIndex {
            sceneIndex = state.scene; started = Date()
            let scene = RoomCatalog.scenes[sceneIndex]
            // Replace a decoded image atomically; the previous scene stays visible until it is ready.
            if let image = SceneImages.shared.image(scene.file + ".png") { room.contents = image }
            rect(room,[0,0,scene.w,scene.h])
            room.opacity = sceneIndex == 6 ? 0.64 : 1
            windowPhoto.isHidden = scene.glass == nil
            if let glass = scene.glass {
                rect(windowPhoto,glass)
                if let image=SceneImages.shared.image("rain-window.jpg") {
                    windowImage.contents=image
                    rect(windowImage,[-glass[2]*0.05,0,glass[2]*1.1,glass[2]*1.1*Double(image.height)/Double(image.width)])
                }
                rect(windowShade,[0,0,glass[2],glass[3]])
                windowShade.opacity = sceneIndex == 6 ? 0.7 : sceneIndex == 5 ? 0.28 : 0.12
                windowPhoto.backgroundColor = NSColor.black.cgColor
            } else { windowImage.contents = nil }
            if let quad=scene.quad { project(sleeve,quad) }
            else if let s=scene.sleeve {
                sleeve.anchorPoint=CGPoint(x:0.5,y:1); sleeve.bounds=CGRect(x:0,y:0,width:s[2],height:s[2]); sleeve.position=CGPoint(x:s[0]+s[2]/2,y:s[1]+s[2]); sleeve.setAffineTransform(CGAffineTransform(rotationAngle:s[3] * .pi / 180))
            }
            let d=scene.disc[2]
            recordPlane.anchorPoint=CGPoint(x:0.5,y:0.5); recordPlane.bounds=CGRect(x:0,y:0,width:d,height:d);recordPlane.position=CGPoint(x:scene.disc[0],y:scene.disc[1]);recordPlane.setAffineTransform(CGAffineTransform(scaleX:1,y:scene.disc[3]))
            record.bounds=recordPlane.bounds;record.position=CGPoint(x:d/2,y:d/2)
            label.frame=CGRect(x:d*0.35,y:d*0.35,width:d*0.3,height:d*0.3);label.cornerRadius=d*0.15
            sleeveShade.frame=sleeve.bounds;sleeveShade.opacity=Float(1-scene.artworkBrightness)
            labelShade.frame=label.bounds;labelShade.opacity=Float(1-scene.artworkBrightness)
            spindle.frame=CGRect(x:d*0.492,y:d*0.492,width:d*0.016,height:d*0.016);spindle.cornerRadius=d*0.008
            let a=scene.arm;rect(arm,[a[0],a[1]+a[2]*0.29*(1-a[3]),a[2],a[2]*a[3]]);arm.contents=SceneImages.shared.image("tonearm-\(sceneIndex == 0 ? "overhead" : "angled").png",maxSize:600)
            historyKey=nil; configureFire(scene)
            rain.select(sceneIndex);rain.setForegroundOcclusion(scene.quad ?? []);needsLayout=true;layoutSubtreeIfNeeded()
        }
        let art=state.track?.art ?? ""
        if art != artKey { let image=art.isEmpty ? nil : SceneImages.shared.image(art,maxSize:512);sleeve.contents=image;label.contents=image;artKey=art }
        if state.history != historyKey {
            history.sublayers?.forEach { $0.removeFromSuperlayer() }
            let h=RoomCatalog.scenes[sceneIndex].history, tracks=Array(state.history.prefix(6))
            for (i,track) in tracks.reversed().enumerated() {
                let card=CALayer(),depth=Double(tracks.count-1-i),size=h[2],cy=h[1]
                card.bounds=CGRect(x:0,y:0,width:size,height:size);card.position=CGPoint(x:h[0]+size/2+depth*2.5,y:cy+depth*1.7)
                var t=CATransform3DIdentity;t.m34 = -1/1000
                t=CATransform3DRotate(t,-6 * .pi / 180,0,0,1);t=CATransform3DRotate(t,h[3] * .pi / 180,1,0,0)
                card.transform=t;card.contents=SceneImages.shared.image(track.art,maxSize:512);card.borderWidth=3;card.borderColor=NSColor(srgbRed:0.8,green:0.75,blue:0.66,alpha:1).cgColor
                card.backgroundColor=NSColor.brown.cgColor
                let shade=CALayer();shade.frame=card.bounds;shade.backgroundColor=NSColor.black.cgColor;shade.opacity=Float(1-RoomCatalog.scenes[sceneIndex].artworkBrightness*0.85);card.addSublayer(shade)
                history.addSublayer(card)
            }
            historyKey=state.history
        }
        playing=state.playing; syncMotion()
        let track=state.track.map { "\($0.name) by \($0.artist)" } ?? "Play a song in Spotify to see its cover"
        setAccessibilityLabel("\(RoomCatalog.scenes[sceneIndex].name). \(track). \(state.playing ? "Playing" : "Paused").")
        CATransaction.commit()
    }
    private func configureFire(_ scene: RoomScene) {
        player?.pause();fireLayer.player=nil;looper=nil;player=nil
        fireLayer.isHidden=scene.fire == nil
        guard let fire=scene.fire else { return }
        rect(fireLayer,fire)
        let player=AVQueuePlayer();player.isMuted=true
        let item=AVPlayerItem(url:Bundle.main.resourceURL!.appendingPathComponent("assets/fire-live.mp4"))
        item.preferredForwardBufferDuration=2
        looper=AVPlayerLooper(player:player,templateItem:item);self.player=player;fireLayer.player=player
        if active && !preferences.effectiveReduceMotion { player.play() }
    }
    private func syncMotion() {
        if playing && active && !preferences.effectiveReduceMotion {
            if record.animation(forKey:"spin") == nil { let angle=atan2(record.transform.m12,record.transform.m11);let spin=CABasicAnimation(keyPath:"transform.rotation.z");spin.fromValue=angle;spin.toValue=angle+Double.pi*2;spin.duration=1.8;spin.repeatCount = .infinity;record.add(spin,forKey:"spin") }
        } else if record.animation(forKey:"spin") != nil {
            let transform=record.presentation()?.transform ?? record.transform;record.removeAnimation(forKey:"spin");record.transform=transform
        }
    }
    func applyPreferences(_ value:VisualPreferences) { preferences=value;rain.setLightningEnabled(value.lightning && !value.effectiveReduceMotion);syncActivity() }
    func setActive(_ value: Bool) { guard active != value else { return };active=value;syncActivity() }
    private func syncActivity() {
        syncMotion()
        let moving=active && !preferences.effectiveReduceMotion
        if moving { player?.play() } else { player?.pause() }
        rain.setPaused(!moving)
    }
    func report() -> [String:Any] { ["scene":sceneIndex,"driver":"native layers","seconds":Int(Date().timeIntervalSince(started)),"artLoaded":sleeve.contents != nil,"historyCount":historyKey?.count ?? 0,"nativeRain":rain.report(),"fireTime":player?.currentTime().seconds ?? 0] }
    func stop() { player?.pause();fireLayer.player=nil;looper=nil;player=nil;rain.select(-1) }
}
