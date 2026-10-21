import AppKit
import ATEMConverter

// `--self-check` lets the packaging script confirm the assembled bundle launches its code.
if CommandLine.arguments.contains("--self-check") {
    print("ATEM ISO to FCPXML \(converterVersion): engine OK")
    exit(0)
}
if CommandLine.arguments.contains("--version") {
    print(converterVersion)
    exit(0)
}
ATEMApp.main()
