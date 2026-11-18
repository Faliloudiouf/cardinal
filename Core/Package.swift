// swift-tools-version: 6.0
// Moteur de Cardinal, sans interface : modèle, MCD → MLD, SQL des 6 SGBD, rétroconception,
// lecture des fichiers Looping, validation et mise en page des diagrammes.
// Il se compile seul (swift build / swift test) : c'est la base des versions Windows et Linux.
import PackageDescription

let package = Package(
    name: "CardinalCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "CardinalCore", targets: ["CardinalCore"]),
    ],
    targets: [
        .target(name: "CardinalCore"),
        .testTarget(
            name: "CardinalCoreTests",
            dependencies: ["CardinalCore"],
            exclude: ["Fixtures"]
        ),
    ]
)
