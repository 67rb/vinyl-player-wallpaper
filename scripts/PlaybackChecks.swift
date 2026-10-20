import Foundation
@main struct PlaybackChecks {
 static func main() {
  func track(_ id:String)->Track { Track(id:id,name:id,artist:"Artist",art:"image") }
  var p=Playback()
  p.receive(track("a"),playing:true);p.receive(track("a"),playing:true)
  precondition(p.history.isEmpty,"Polling duplicated current song")
  p.receive(track("b"),playing:true)
  precondition(p.history.map(\.id)==["a"],"Previous played song missing")
  p.receive(track("c"),playing:true);p.receive(track("a"),playing:true)
  precondition(p.history.map(\.id)==["c","b","a"],"Repeated track was not moved to most recent position")
  p.receive(track("a"),playing:false)
  precondition(!p.playing,"Pause did not stop playback")
  p.receive(track("d"),playing:false);p.receive(track("e"),playing:false)
  precondition(p.history.map(\.id)==["a","c","b"],"Paused browsing added unplayed song")
  p.scene=3
  for i in 0..<12 { p.receive(track(String(i)),playing:true) }
  precondition(p.history.count==6 && p.history.first?.id=="10","History order or limit incorrect")
  precondition(p.scene==3,"Playback changed scene")
  let roundtrip=try! JSONDecoder().decode(Playback.self,from:JSONEncoder().encode(p))
  precondition(roundtrip.track==p.track && roundtrip.history==p.history,"Saved state lost data")
  p.history=[Track(id:"spotify:media:spotify:track:z",name:"Up next",artist:"",art:""),track("z"),track("z"),track("y"),track("z")];p.normalizeHistory()
  precondition(p.history.map(\.id)==["z","y"],"Loaded history kept repeated song jackets")
  print("PASS: track changes, repeated polling, paused browsing, pause state, six-song bound, scene retention, Codable roundtrip")
 }
}
