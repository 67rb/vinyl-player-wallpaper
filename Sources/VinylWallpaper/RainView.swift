import AppKit
import QuartzCore

// The desktop rain uses compositor animations rather than a JavaScript frame
// bridge. Repeating transparent tiles preserve density without one layer per drop.
final class RainView: NSView {
    private static let tiles: NSCache<NSString, CGImage> = {
        let cache=NSCache<NSString,CGImage>();cache.countLimit=5;cache.totalCostLimit=14*1024*1024;return cache
    }()
    override var isFlipped: Bool { true }
    var sceneIndex = -1
    var previousSize = NSSize.zero
    private let glass = CALayer()
    private var lightningEnabled = true
    private var paused = false
    func setLightningEnabled(_ value:Bool) { guard lightningEnabled != value else { return };lightningEnabled=value;rebuild() }
    func setForegroundOcclusion(_ quad:[[Double]]) {
        guard quad.count == 4 else { glass.mask=nil;return }
        let path=CGMutablePath();path.addRect(CGRect(x:0,y:0,width:1228,height:535))
        // This layer tree's local vertical axis points upward.
        path.move(to:CGPoint(x:quad[0][0]-187,y:535-quad[0][1]))
        for point in quad.dropFirst() { path.addLine(to:CGPoint(x:point[0]-187,y:535-point[1])) }
        path.closeSubpath()
        let mask=CAShapeLayer();mask.frame=glass.bounds;mask.path=path;mask.fillRule = .evenOdd;glass.mask=mask
    }
    func setPaused(_ value:Bool) {
        guard paused != value,let layer else { return }
        paused=value
        if value { layer.timeOffset=layer.convertTime(CACurrentMediaTime(),from:nil);layer.speed=0 }
        else { let time=layer.timeOffset;layer.speed=1;layer.timeOffset=0;layer.beginTime=0;layer.beginTime=layer.convertTime(CACurrentMediaTime(),from:nil)-time }
    }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.isGeometryFlipped = true
        glass.masksToBounds = true
        glass.isGeometryFlipped = true
        layer?.addSublayer(glass)
    }
    required init?(coder: NSCoder) { fatalError() }
    func select(_ scene: Int) {
        guard sceneIndex != scene else { return }
        sceneIndex = scene
        rebuild()
    }
    override func layout() {
        super.layout()
        guard bounds.size != previousSize else { return }
        previousSize = bounds.size
        positionGlass()
    }
    private func positionGlass() {
        let scale = max(bounds.width / 1586, bounds.height / 992)
        let offsetX = (bounds.width - 1586 * scale) / 2
        let offsetY = (bounds.height - 992 * scale) / 2
        CATransaction.begin(); CATransaction.setDisableActions(true)
        glass.bounds = CGRect(x: 0, y: 0, width: 1228, height: 535)
        glass.anchorPoint = .zero
        glass.position = CGPoint(x: offsetX + 187 * scale, y: offsetY)
        glass.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        CATransaction.commit()
    }
    func report() -> [String:Any] {
        let offsets = (glass.sublayers ?? []).compactMap { child -> Double? in
            guard child.animation(forKey:"rain") != nil, let shown = child.presentation() else { return nil }
            return Double(shown.transform.m42)
        }
        return ["scene":sceneIndex,"layers":glass.sublayers?.count ?? 0,"offsets":offsets,"hidden":glass.isHidden,"paused":paused,"lightningEnabled":lightningEnabled,"foregroundMasked":glass.mask != nil,"frame":[Double(glass.frame.minX),Double(glass.frame.minY),Double(glass.frame.width),Double(glass.frame.height)]]
    }
    private func tile(count: Int, droplets: Bool, intensity: Double, seed: Int) -> CGImage? {
        let key="\(count):\(droplets):\(intensity):\(seed)" as NSString
        if let image=Self.tiles.object(forKey:key) { return image }
        let width = 1228, height = 535
        guard let context = CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Stable per-scene positions avoid changing the view on every resize.
        var rng = UInt64(seed + 17)
        func random(_ lower: Double, _ upper: Double) -> Double {
            rng = rng &* 6364136223846793005 &+ 1
            return lower + Double((rng >> 32) & 0xffff) / 65535 * (upper - lower)
        }
        for _ in 0..<count {
            let x = random(4,1224), y = random(0,535)
            if droplets {
                let radius = random(0.8,2.6), trail = random(18,65) * intensity
                context.setStrokeColor(CGColor(red:0.84,green:0.92,blue:0.96,alpha:0.18))
                context.setLineWidth(radius * 0.65)
                context.move(to:CGPoint(x:x,y:y)); context.addCurve(to:CGPoint(x:x,y:y+trail),control1:CGPoint(x:x-2,y:y+trail*0.3),control2:CGPoint(x:x+3,y:y+trail*0.8)); context.strokePath()
                context.setFillColor(CGColor(red:0.08,green:0.15,blue:0.18,alpha:0.22)); context.fillEllipse(in:CGRect(x:x-radius,y:y-radius*1.8,width:radius*2,height:radius*3.6))
                context.setStrokeColor(CGColor(red:0.87,green:0.94,blue:0.97,alpha:0.5));context.setLineWidth(0.55)
                context.strokeEllipse(in:CGRect(x:x-radius*0.7,y:y-radius*1.5,width:radius*1.4,height:radius*3))
            } else {
                let length = random(9,26) * intensity
                context.setStrokeColor(CGColor(red:0.82,green:0.89,blue:0.93,alpha:random(0.09,0.27)));context.setLineWidth(random(0.45,1.1))
                context.move(to:CGPoint(x:x,y:y));context.addLine(to:CGPoint(x:x+length*0.075,y:y+length));context.strokePath()
            }
        }
        guard let image=context.makeImage() else { return nil }
        Self.tiles.setObject(image,forKey:key,cost:image.bytesPerRow*image.height)
        return image
    }
    private func addRain(count: Int, droplets: Bool, intensity: Double, speed: Double, seed: Int) {
        guard let image = tile(count:count,droplets:droplets,intensity:intensity,seed:seed) else { return }
        let belt = CALayer(); belt.frame = CGRect(x:0,y:-535,width:1228,height:1070)
        for y in [0,535] {
            let tile = CALayer();tile.frame = CGRect(x:0,y:y,width:1228,height:535);tile.contents = image;tile.contentsGravity = .resize
            belt.addSublayer(tile)
        }
        glass.addSublayer(belt)
        let motion = CABasicAnimation(keyPath:"transform.translation.y")
        // Decreasing translation moves the tiles down in this flipped layer tree.
        motion.fromValue = 535;motion.toValue = 0;motion.duration = 535 / speed
        motion.repeatCount = .infinity;motion.timingFunction = CAMediaTimingFunction(name:.linear)
        belt.add(motion,forKey:"rain")
    }
    private func rebuild() {
        CATransaction.begin();CATransaction.setDisableActions(true)
        glass.sublayers?.forEach { $0.removeFromSuperlayer() }
        glass.isHidden = !(4...6).contains(sceneIndex)
        positionGlass()
        guard !glass.isHidden else { CATransaction.commit(); return }
        let intensity = Double(sceneIndex - 3)
        let streaks = [120,720,1050][sceneIndex-4], drops = [65,260,360][sceneIndex-4]
        glass.backgroundColor = CGColor(red:0.64,green:0.73,blue:0.78,alpha:intensity==3 ? 0.065 : intensity==2 ? 0.035 : 0)
        for bucket in 0..<3 {
            addRain(count:streaks/3,droplets:false,intensity:intensity,speed:(380+Double(bucket)*152)*sqrt(intensity),seed:bucket+sceneIndex*41)
        }
        for bucket in 0..<2 {
            addRain(count:drops/2,droplets:true,intensity:intensity,speed:(25+Double(bucket)*26)*intensity,seed:bucket+sceneIndex*71)
        }
        if sceneIndex == 6 && lightningEnabled {
            let flash = CALayer();flash.frame = CGRect(x:0,y:0,width:1228,height:535);flash.backgroundColor = CGColor(red:0.73,green:0.82,blue:1,alpha:1);flash.opacity = 0;glass.addSublayer(flash)
            let flicker = CAKeyframeAnimation(keyPath:"opacity");flicker.values = [0,0,0.6,0.08,0.4,0,0];flicker.keyTimes = [0,0.72,0.73,0.74,0.75,0.78,1];flicker.duration = 16;flicker.repeatCount = .infinity;flash.add(flicker,forKey:"lightning")
        }
        CATransaction.commit()
    }
}
