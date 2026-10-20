import AVFoundation

final class AmbientSound {
    private var bed: AVAudioPlayer?
    private var thunder: AVAudioPlayer?
    private var kind = ""
    private var nextThunder = Date.distantFuture
    private var volume: Float = 0
    func update(scene: Int, enabled: Bool, volume: Double) {
        guard enabled, scene >= 4 else { bed?.stop();bed=nil;thunder?.stop();thunder=nil;kind="";nextThunder = .distantFuture;return }
        let next=scene == 7 ? "fire" : scene == 6 ? "storm" : "rain"
        if next != kind {
            bed?.stop();kind=next
            let url=Bundle.main.resourceURL!.appendingPathComponent("assets/ambient-\(next).wav")
            bed=try? AVAudioPlayer(contentsOf:url);bed?.numberOfLoops = -1
            if scene == 6 { nextThunder=Date().addingTimeInterval(13.8) } else { thunder?.stop();thunder=nil;nextThunder = .distantFuture }
            bed?.play()
        }
        self.volume=Float(volume)
        bed?.volume=Float(volume * (scene == 7 ? 0.32 : Double(scene-3)*0.19))
    }
    func tick() {
        guard kind == "storm", Date() >= nextThunder else { return }
        thunder=try? AVAudioPlayer(contentsOf:Bundle.main.resourceURL!.appendingPathComponent("assets/ambient-thunder.wav"))
        thunder?.volume=volume;thunder?.play();nextThunder=Date().addingTimeInterval(16)
    }
}
