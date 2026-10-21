import Foundation

@main struct AudioSelectionTests {
    static func main() {
        let cameras = [Camera(id: 1, name: "One", used: true, wav: "one.wav"),
                       Camera(id: 2, name: "Two", used: true, wav: "two.wav"),
                       Camera(id: 3, name: "Three", used: false, wav: "three.wav")]
        // Exercise every camera subset and soundtrack, including a mic-only source.
        let audio = ["one.wav", "two.wav", "three.wav", "mic.wav"]
        for mask in 0..<8 {
            let selected = Set((1...3).filter { mask & (1 << ($0 - 1)) != 0 })
            for soundtrack in audio {
                for source in audio {
                    let result = inclusionReason(source, cameras: cameras, selected: selected, soundtrack: soundtrack)
                    if source == soundtrack { precondition(result == "Soundtrack") }
                    else if cameras.contains(where: { selected.contains($0.id) && $0.wav == source }) {
                        precondition(result == "With camera")
                    } else { precondition(result == nil) }
                }
            }
        }
        print("128 audio inclusion combinations passed")
    }
}
