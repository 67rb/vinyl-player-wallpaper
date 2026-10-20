import Foundation

struct RoomScene: Decodable {
    let name: String
    let subtitle: String
    let mood: String
    let description: String
    let file: String
    let w: Double
    let h: Double
    let disc: [Double]
    let sleeve: [Double]?
    let quad: [[Double]]?
    let arm: [Double]
    let history: [Double]
    let glass: [Double]?
    let fire: [Double]?
    let effect: String

    var artworkBrightness: Double {
        switch file { case "after-hours": return 0.68;case "rain-light","rain-heavy":return 0.80;case "rain-storm":return 0.58;case "fireside":return 0.72;default:return 1 }
    }
}

enum RoomCatalog {
    static let scenes: [RoomScene] = {
        guard let url=Bundle.main.url(forResource:"scenes",withExtension:"json") else { return [] }
        return (try? load(url)) ?? []
    }()
    static func load(_ url:URL) throws -> [RoomScene] {
        let scenes=try JSONDecoder().decode([RoomScene].self,from:Data(contentsOf:url))
        guard !scenes.isEmpty, scenes.allSatisfy({ scene in
            scene.w > 0 && scene.h > 0 && scene.disc.count == 4 && scene.disc.allSatisfy(\.isFinite) && scene.disc[2] > 0 && scene.disc[3] > 0 &&
            scene.arm.count == 4 && scene.history.count == 4 &&
            (scene.sleeve?.count == 4 || (scene.quad?.count == 4 && scene.quad!.allSatisfy { $0.count == 2 && $0.allSatisfy(\.isFinite) })) &&
            (scene.glass == nil || scene.glass?.count == 4) && (scene.fire == nil || scene.fire?.count == 4)
        }) else { throw NSError(domain:"VinylWallpaper.RoomCatalog",code:1,userInfo:[NSLocalizedDescriptionKey:"The room geometry is incomplete."]) }
        return scenes
    }
}
