import Foundation

struct Camera: Decodable, Identifiable { let id: Int; let name: String; let used: Bool; let wav: String? }
struct Audio: Decodable, Identifiable { let id: String; let name: String }
struct Recording: Decodable {
    let path: String; let name: String; let output: String
    let cameras: [Camera]; let audio: [Audio]; let soundtrack: String; let warnings: [String]
}

// One source can already belong to a camera or be the continuous soundtrack.
// Only the remaining sources can become additional audio-only angles.
func inclusionReason(_ audio: String, cameras: [Camera], selected: Set<Int>, soundtrack: String) -> String? {
    if audio == soundtrack { return "Soundtrack" }
    if cameras.contains(where: { selected.contains($0.id) && $0.wav == audio }) { return "With camera" }
    return nil
}
