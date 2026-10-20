import AppKit

struct VisualPreferences: Equatable {
    var enabled = true
    var sound = false
    var volume = 0.15
    var reduceMotion = false
    var lightning = true
    var systemReduceMotion = false
    var effectiveReduceMotion: Bool { reduceMotion || systemReduceMotion }
}

enum CollectionAction {
    case scene(Int), enabled(Bool), sound(Bool), volume(Double), reduceMotion(Bool), lightning(Bool)
    case preview, spotify, reconnect, privacy, clear, undoClear
}

private enum Palette {
    static let background = NSColor(srgbRed:0.086,green:0.09,blue:0.082,alpha:1)
    static let sidebar = NSColor(srgbRed:0.106,green:0.11,blue:0.098,alpha:1)
    static let text = NSColor(srgbRed:0.93,green:0.94,blue:0.90,alpha:1)
    static let muted = NSColor(srgbRed:0.65,green:0.67,blue:0.62,alpha:1)
    static let accent = NSColor(srgbRed:0.84,green:0.71,blue:0.53,alpha:1)
}

class FlippedView: NSView { override var isFlipped: Bool { true } }

private final class RoomCard: NSButton {
    let sceneIndex: Int
    private let photo = NSImageView()
    private let nameLabel = NSTextField(labelWithString:"")
    private let detailLabel = NSTextField(labelWithString:"")
    private let check = NSImageView()
    var choose: ((Int) -> Void)?
    var navigate: ((Int) -> Void)?
    var columns = 4
    var selected = false { didSet { check.isHidden = !selected; setAccessibilityValue(selected ? 1 : 0); needsDisplay=true } }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(index:Int) {
        sceneIndex=index
        super.init(frame:.zero)
        let scene=RoomCatalog.scenes[index]
        title="";isBordered=false;target=self;action=#selector(activate)
        setAccessibilityRole(.radioButton);setAccessibilityLabel("\(scene.name) wallpaper");setAccessibilityHelp(scene.subtitle)
        photo.imageScaling = .scaleAxesIndependently
        if let image=SceneImages.shared.image("thumbnails/\(scene.file).jpg",maxSize:500) { photo.image=NSImage(cgImage:image,size:.zero) }
        photo.wantsLayer=true;photo.layer?.cornerRadius=9;photo.layer?.masksToBounds=true
        nameLabel.stringValue=scene.name;nameLabel.font = .systemFont(ofSize:13,weight:.medium);nameLabel.textColor=Palette.text
        detailLabel.stringValue=scene.subtitle;detailLabel.font = .systemFont(ofSize:11);detailLabel.textColor=Palette.muted;detailLabel.lineBreakMode = .byTruncatingTail
        check.image=NSImage(systemSymbolName:"checkmark.circle.fill",accessibilityDescription:nil);check.contentTintColor=Palette.accent;check.isHidden=true
        for view in [photo,nameLabel,detailLabel,check] { view.setAccessibilityElement(false);addSubview(view) }
    }
    required init?(coder:NSCoder) { fatalError() }
    override func hitTest(_ point:NSPoint) -> NSView? { bounds.contains(convert(point,from:superview)) ? self : nil }
    @objc private func activate() { choose?(sceneIndex) }
    override func keyDown(with event:NSEvent) {
        let offsets:[UInt16:Int]=[123:-1,124:1,125:columns,126:-columns]
        if let offset=offsets[event.keyCode] { navigate?(sceneIndex+offset) } else { super.keyDown(with:event) }
    }
    override func layout() {
        super.layout()
        let h=max(70,bounds.height-43)
        photo.frame=NSRect(x:2,y:2,width:bounds.width-4,height:h-4)
        nameLabel.frame=NSRect(x:2,y:h+8,width:bounds.width-4,height:18)
        detailLabel.frame=NSRect(x:2,y:h+27,width:bounds.width-4,height:15)
        check.frame=NSRect(x:bounds.width-28,y:h-28,width:21,height:21)
    }
    override func draw(_ dirtyRect:NSRect) {
        let rect=NSRect(x:1,y:1,width:bounds.width-2,height:bounds.height-44)
        let path=NSBezierPath(roundedRect:rect,xRadius:10,yRadius:10)
        (selected ? Palette.accent : NSColor.white.withAlphaComponent(0.12)).setStroke();path.lineWidth=selected ? 2 : 1;path.stroke()
        if window?.firstResponder === self { Palette.accent.setStroke();let focus=NSBezierPath(roundedRect:bounds.insetBy(dx:0.5,dy:0.5),xRadius:11,yRadius:11);focus.lineWidth=2;focus.stroke() }
    }
}

final class CollectionView: FlippedView {
    var onAction: ((CollectionAction) -> Void)?
    private let sidebar=FlippedView(), scroll=NSScrollView(), document=FlippedView()
    private let hero=SceneView(frame:.zero)
    private let heroShade=CAGradientLayer()
    private let brand=NSTextField(labelWithString:"vinyl")
    private let tagline=NSTextField(labelWithString:"A ROOM FOR YOUR MUSIC")
    private let collectionLabel=NSTextField(labelWithString:"THE COLLECTION")
    private let heading=NSTextField(labelWithString:"Find your atmosphere.")
    private let subtitle=NSTextField(labelWithString:"Eight rooms. The music is yours.")
    private let sectionTitle=NSTextField(labelWithString:"")
    private let heroTitle=NSTextField(labelWithString:"")
    private let connection=NSTextField(wrappingLabelWithString:"")
    private let note=NSTextField(wrappingLabelWithString:"Put a record on.\nMake yourself at home.")
    private let notice=NSTextField(wrappingLabelWithString:"")
    private let historyLabel=NSTextField(labelWithString:"")
    private let playbackLabel=NSTextField(labelWithString:"")
    private let trackTitle=NSTextField(labelWithString:"")
    private let trackArtist=NSTextField(labelWithString:"")
    private let nowArt=NSImageView()
    private let enabled=NSSwitch(), sound=NSSwitch(), volume=NSSlider(value:15,minValue:0,maxValue:50,target:nil,action:nil)
    private let enabledLabel=NSTextField(labelWithString:"Live wallpaper")
    private let soundLabel=NSTextField(labelWithString:"Room sounds")
    private let volumeLabel=NSTextField(labelWithString:"15%")
    private let soundHint=NSTextField(labelWithString:"")
    private let motion=NSButton(checkboxWithTitle:"Reduce motion",target:nil,action:nil)
    private let lightning=NSButton(checkboxWithTitle:"Lightning flashes",target:nil,action:nil)
    private let comfortLabel=NSTextField(labelWithString:"COMFORT")
    private var cards:[RoomCard]=[]
    private var navRooms=NSButton(),navAmbience=NSButton(),openSpotify=NSButton(),reconnect=NSButton(),privacy=NSButton(),preview=NSButton(),clear=NSButton(),undo=NSButton()
    private var controlsY:CGFloat=0
    private var currentArt=""
    private var viewActive=true
    private var preferences=VisualPreferences()

    override init(frame:NSRect) {
        super.init(frame:frame)
        appearance=NSAppearance(named:.darkAqua)
        wantsLayer=true;layer?.backgroundColor=Palette.background.cgColor
        sidebar.wantsLayer=true;sidebar.layer?.backgroundColor=Palette.sidebar.cgColor
        addSubview(sidebar);addSubview(scroll)
        scroll.documentView=document;scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true;scroll.drawsBackground=false
        brand.font=NSFont(name:"Georgia",size:38);brand.textColor=Palette.text
        tagline.font = .systemFont(ofSize:9,weight:.medium);tagline.textColor=Palette.muted
        connection.font = .systemFont(ofSize:12);connection.textColor=Palette.muted
        note.font=NSFont(name:"Georgia",size:21);note.textColor=Palette.text.withAlphaComponent(0.8)
        for label in [brand,tagline,connection,note] { sidebar.addSubview(label) }
        navRooms=button("Wallpapers",symbol:"square.grid.2x2",action:#selector(scrollRooms));navAmbience=button("Playback & ambience",symbol:"slider.horizontal.3",action:#selector(scrollAmbience))
        openSpotify=button("Open Spotify",symbol:"arrow.up.right",action:#selector(spotifyClicked));reconnect=button("Reconnect Spotify",action:#selector(reconnectClicked));privacy=button("Automation settings",action:#selector(privacyClicked))
        for button in [navRooms,navAmbience,openSpotify,reconnect,privacy] { sidebar.addSubview(button) }
        for label in [collectionLabel,comfortLabel] { label.font = .systemFont(ofSize:10,weight:.semibold);label.textColor=Palette.muted }
        heading.font=NSFont(name:"Georgia",size:32);heading.textColor=Palette.text
        subtitle.font = .systemFont(ofSize:13);subtitle.textColor=Palette.muted
        sectionTitle.font = .systemFont(ofSize:14,weight:.medium);sectionTitle.textColor=Palette.text
        enabledLabel.font = .systemFont(ofSize:12);enabledLabel.textColor=Palette.text
        document.addSubview(hero)
        hero.wantsLayer=true;hero.layer?.cornerRadius=12;hero.layer?.masksToBounds=true
        heroShade.colors=[NSColor.clear.cgColor,NSColor.black.withAlphaComponent(0.65).cgColor];heroShade.startPoint=CGPoint(x:0.5,y:0);heroShade.endPoint=CGPoint(x:0.5,y:1)
        hero.layer?.addSublayer(heroShade)
        heroTitle.font=NSFont(name:"Georgia",size:23);heroTitle.textColor = .white;hero.addSubview(heroTitle)
        preview=button("Open live preview",symbol:"arrow.up.right",action:#selector(previewClicked));hero.addSubview(preview)
        enabled.target=self;enabled.action=#selector(enabledChanged);enabled.setAccessibilityLabel("Enable live wallpaper")
        sound.target=self;sound.action=#selector(soundChanged);sound.setAccessibilityLabel("Enable room sounds")
        volume.target=self;volume.action=#selector(volumeChanged);volume.isContinuous=true;volume.setAccessibilityLabel("Room sound volume")
        motion.target=self;motion.action=#selector(motionChanged);lightning.target=self;lightning.action=#selector(lightningChanged)
        motion.toolTip="Stops record, rain and fire animation. Also follows the macOS Reduce motion setting."
        lightning.toolTip="Show lightning in the Thunderstorm room. Reduced motion always disables flashes."
        soundLabel.font = .systemFont(ofSize:13,weight:.medium);soundLabel.textColor=Palette.text
        for label in [soundHint,volumeLabel,historyLabel,trackArtist,notice] { label.font = .systemFont(ofSize:11);label.textColor=Palette.muted }
        notice.textColor=Palette.accent
        playbackLabel.font = .systemFont(ofSize:10,weight:.medium);playbackLabel.textColor=Palette.accent
        trackTitle.font = .systemFont(ofSize:14,weight:.semibold);trackTitle.textColor=Palette.text;trackTitle.lineBreakMode = .byTruncatingTail
        trackArtist.lineBreakMode = .byTruncatingTail
        nowArt.imageScaling = .scaleProportionallyUpOrDown;nowArt.wantsLayer=true;nowArt.layer?.cornerRadius=6;nowArt.layer?.masksToBounds=true
        clear=button("Clear played records",action:#selector(clearClicked));undo=button("Undo clear",action:#selector(undoClicked));undo.isHidden=true
        for view in [collectionLabel,heading,subtitle,sectionTitle,enabledLabel,enabled,nowArt,playbackLabel,trackTitle,trackArtist,soundLabel,soundHint,sound,volume,volumeLabel,comfortLabel,motion,lightning,historyLabel,clear,undo,notice] { document.addSubview(view) }
        for i in RoomCatalog.scenes.indices {
            let card=RoomCard(index:i)
            card.choose={ [weak self] in self?.onAction?(.scene($0)) }
            card.navigate={ [weak self] next in guard let self,self.cards.indices.contains(next) else { return };self.window?.makeFirstResponder(self.cards[next]);self.cards[next].scrollToVisible(self.cards[next].bounds);self.onAction?(.scene(next)) }
            cards.append(card);document.addSubview(card)
        }
    }
    required init?(coder:NSCoder) { fatalError() }
    private func button(_ title:String,symbol:String?=nil,action:Selector)->NSButton {
        let button=NSButton(title:title,target:self,action:action);button.bezelStyle = .rounded;button.font = .systemFont(ofSize:12)
        if let symbol { button.image=NSImage(systemSymbolName:symbol,accessibilityDescription:nil);button.imagePosition = .imageLeading }
        return button
    }
    override func layout() {
        super.layout()
        let side:CGFloat=bounds.width<1000 ? 180 : 204,pad:CGFloat=26
        sidebar.frame=NSRect(x:0,y:0,width:side,height:bounds.height)
        scroll.frame=NSRect(x:side,y:0,width:bounds.width-side,height:bounds.height)
        let w=scroll.contentSize.width,inner=w-pad*2
        brand.frame=NSRect(x:24,y:32,width:side-40,height:48);tagline.frame=NSRect(x:25,y:85,width:side-40,height:15)
        navRooms.frame=NSRect(x:20,y:140,width:side-40,height:34);navAmbience.frame=NSRect(x:20,y:182,width:side-40,height:34)
        connection.frame=NSRect(x:24,y:237,width:side-46,height:74)
        note.frame=NSRect(x:24,y:max(330,bounds.height-264),width:side-45,height:112)
        openSpotify.frame=NSRect(x:20,y:bounds.height-140,width:side-40,height:30)
        reconnect.frame=NSRect(x:20,y:bounds.height-101,width:side-40,height:30)
        privacy.frame=NSRect(x:20,y:bounds.height-62,width:side-40,height:30)
        collectionLabel.frame=NSRect(x:pad,y:26,width:inner,height:16)
        heading.frame=NSRect(x:pad,y:49,width:inner-150,height:42)
        subtitle.frame=NSRect(x:pad,y:95,width:inner,height:20)
        enabledLabel.frame=NSRect(x:w-pad-140,y:64,width:104,height:20);enabled.frame=NSRect(x:w-pad-36,y:59,width:36,height:25)
        let heroHeight=min(300,inner*0.36)
        hero.frame=NSRect(x:pad,y:133,width:inner,height:heroHeight)
        heroShade.frame=NSRect(x:0,y:heroHeight-90,width:inner,height:90)
        heroTitle.frame=NSRect(x:20,y:heroHeight-52,width:inner-224,height:34)
        preview.frame=NSRect(x:inner-175,y:heroHeight-51,width:155,height:32)
        sectionTitle.frame=NSRect(x:pad,y:hero.frame.maxY+25,width:inner,height:23)
        let columns=inner<580 ? 3 : 4,gap:CGFloat=14,cardWidth=(inner-CGFloat(columns-1)*gap)/CGFloat(columns),cardHeight=cardWidth*0.62+43
        let gridY=sectionTitle.frame.maxY+13
        for (i,card) in cards.enumerated() { card.columns=columns;card.frame=NSRect(x:pad+CGFloat(i%columns)*(cardWidth+gap),y:gridY+CGFloat(i/columns)*(cardHeight+16),width:cardWidth,height:cardHeight) }
        controlsY=gridY+CGFloat((cards.count+columns-1)/columns)*(cardHeight+16)+14
        nowArt.frame=NSRect(x:pad,y:controlsY,width:50,height:50)
        playbackLabel.frame=NSRect(x:pad+63,y:controlsY,width:inner/2-65,height:15)
        trackTitle.frame=NSRect(x:pad+63,y:controlsY+17,width:inner/2-65,height:20)
        trackArtist.frame=NSRect(x:pad+63,y:controlsY+39,width:inner/2-65,height:17)
        let sx=pad+inner*0.58
        soundLabel.frame=NSRect(x:sx,y:controlsY,width:140,height:21);sound.frame=NSRect(x:w-pad-36,y:controlsY-2,width:36,height:25)
        soundHint.frame=NSRect(x:sx,y:controlsY+27,width:inner*0.42,height:18)
        volume.frame=NSRect(x:sx,y:controlsY+51,width:inner*0.42-50,height:20);volumeLabel.frame=NSRect(x:w-pad-40,y:controlsY+53,width:40,height:18)
        comfortLabel.frame=NSRect(x:pad,y:controlsY+91,width:inner,height:16)
        motion.frame=NSRect(x:pad,y:controlsY+117,width:185,height:25);lightning.frame=NSRect(x:pad+200,y:controlsY+117,width:190,height:25)
        historyLabel.frame=NSRect(x:pad,y:controlsY+166,width:inner-220,height:18)
        clear.frame=NSRect(x:w-pad-171,y:controlsY+158,width:171,height:30);undo.frame=clear.frame
        notice.frame=NSRect(x:pad,y:controlsY+201,width:inner,height:50)
        document.frame=NSRect(x:0,y:0,width:w,height:controlsY+265)
    }
    func update(_ state:Playback,preferences:VisualPreferences,canUndo:Bool) {
        self.preferences=preferences
        let scene=RoomCatalog.scenes[state.scene]
        sectionTitle.stringValue="Your wallpapers · \(scene.name)";heroTitle.stringValue=scene.name
        connection.stringValue=state.status.hasPrefix("Connected") ? "Spotify connected" : state.status
        notice.stringValue=state.status.contains("Allow") ? state.status : "Closing this window keeps your wallpaper running."
        for (i,card) in cards.enumerated() { card.selected=i == state.scene }
        enabled.state=preferences.enabled ? .on : .off;sound.state=preferences.sound ? .on : .off;volume.doubleValue=preferences.volume*100
        volumeLabel.stringValue="\(Int((preferences.volume*100).rounded()))%"
        let ambient=state.scene>=4;sound.isEnabled=ambient;volume.isEnabled=ambient && preferences.sound
        soundHint.stringValue=ambient ? (preferences.sound ? "Playing quietly in your room" : "Rain, thunder & fire") : "Choose a rain or Fireside room"
        motion.state=preferences.effectiveReduceMotion ? .on : .off;motion.isEnabled = !preferences.systemReduceMotion
        lightning.state=preferences.lightning ? .on : .off;lightning.isEnabled=state.scene == 6 && !preferences.effectiveReduceMotion
        playbackLabel.stringValue=state.playing ? "NOW PLAYING" : "SPOTIFY · PAUSED"
        trackTitle.stringValue=state.track?.name ?? "Your next listening session";trackArtist.stringValue=state.track?.artist ?? "Play a song in Spotify to begin"
        let art=state.track?.art ?? ""
        if art != currentArt { currentArt=art;if let image=SceneImages.shared.image(art,maxSize:512) { nowArt.image=NSImage(cgImage:image,size:.zero) } else { nowArt.image=NSImage(systemSymbolName:"opticaldisc",accessibilityDescription:"No album artwork") } }
        historyLabel.stringValue=state.history.isEmpty ? "Played records will collect beside your turntable." : "\(state.history.count) played records beside your turntable"
        clear.isEnabled = !state.history.isEmpty;clear.isHidden=canUndo;undo.isHidden = !canUndo
        hero.update(state);hero.applyPreferences(preferences);hero.setActive(viewActive)
    }
    func setActive(_ value:Bool) { viewActive=value;hero.setActive(value) }
    func stop() { hero.stop() }
    @objc private func scrollRooms() { scroll.contentView.scroll(to:.zero);scroll.reflectScrolledClipView(scroll.contentView) }
    @objc private func scrollAmbience() { scroll.contentView.scroll(to:CGPoint(x:0,y:controlsY-25));scroll.reflectScrolledClipView(scroll.contentView) }
    @objc private func enabledChanged() { onAction?(.enabled(enabled.state == .on)) }
    @objc private func soundChanged() { onAction?(.sound(sound.state == .on)) }
    @objc private func volumeChanged() { onAction?(.volume(volume.doubleValue/100)) }
    @objc private func motionChanged() { onAction?(.reduceMotion(motion.state == .on)) }
    @objc private func lightningChanged() { onAction?(.lightning(lightning.state == .on)) }
    @objc private func previewClicked() { onAction?(.preview) }
    @objc private func spotifyClicked() { onAction?(.spotify) }
    @objc private func reconnectClicked() { onAction?(.reconnect) }
    @objc private func privacyClicked() { onAction?(.privacy) }
    @objc private func clearClicked() { onAction?(.clear) }
    @objc private func undoClicked() { onAction?(.undoClear) }
}
