// swift-tools-version: 6.0
// Moteur de Cardinal compilé en WebAssembly pour les versions Windows et Linux (et le navigateur).
// Les sources du moteur ne sont pas copiées : « Sources/CardinalWasm/Moteur » est un lien vers Core.
import PackageDescription

let package = Package(
    name: "CardinalWasm",
    targets: [
        .executableTarget(
            name: "CardinalWasm",
            swiftSettings: [.define("CARDINAL_PORTABLE"), .unsafeFlags(["-Osize"])],
            linkerSettings: [.unsafeFlags(["-Xclang-linker", "-mexec-model=reactor", "-Xlinker", "--strip-all"])]
        ),
    ]
)
