// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "atem-iso-to-fcpxml",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ATEMConverter", targets: ["ATEMConverter"]),
        .executable(name: "ATEMISOtoFCPXML", targets: ["ATEMISOtoFCPXML"]),
        .executable(name: "atem-convert", targets: ["atem-convert"]),
    ],
    targets: [
        // The conversion engine: a port of atem_iso_to_fcpxml.py that must produce identical XML.
        .target(name: "ATEMConverter", path: "Sources/ATEMConverter"),
        // The Mac app.
        .executableTarget(name: "ATEMISOtoFCPXML", dependencies: ["ATEMConverter"], path: "Sources/ATEMISOtoFCPXML"),
        // A command-line front end used to compare the Swift engine with the Python reference.
        .executableTarget(name: "atem-convert", dependencies: ["ATEMConverter"], path: "Sources/atem-convert"),
        .testTarget(name: "ATEMConverterTests", dependencies: ["ATEMConverter", "ATEMISOtoFCPXML", "atem-convert"], path: "tests/ATEMConverterTests"),
    ],
    swiftLanguageModes: [.v5]
)
