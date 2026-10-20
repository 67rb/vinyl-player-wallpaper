import Foundation

struct Track: Codable, Equatable {
    var id: String
    var name: String
    var artist: String
    var art: String
}

struct Playback: Codable, Equatable {
    var track: Track?
    var history: [Track] = []
    var playing = false
    var scene = 0
    var status = "Waiting for Spotify"
    private var heardCurrent = false

    mutating func receive(_ next: Track, playing: Bool) {
        if next.id != track?.id {
            if let previous = track, heardCurrent {
                history.removeAll { $0.id == previous.id }
                history.insert(previous, at: 0)
                history = Array(history.prefix(6))
            }
            heardCurrent = false
        }
        track = next
        self.playing = playing
        heardCurrent = heardCurrent || playing
        status = playing ? "Connected · Playing" : "Connected · Paused"
    }

    mutating func normalizeHistory() {
        var seen = Set<String>()
        history = Array(history.filter { !$0.id.hasPrefix("spotify:media:") && seen.insert($0.id).inserted }.prefix(6))
    }
}
