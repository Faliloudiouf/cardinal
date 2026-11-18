import Testing
import Foundation
#if SWIFT_PACKAGE
@testable import CardinalCore
#else
@testable import Cardinal
#endif

/// Le moteur doit rester compilable sous Windows et Linux : aucune bibliothèque d'interface Apple,
/// sauf derrière « #if canImport(…) » avec une solution de repli.
@Suite("Portabilité du moteur")
struct PortabilityTests {
    static let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/CardinalCore")

    @Test("Aucun import Apple non protégé dans le moteur")
    func importsPortables() throws {
        let forbidden = ["AppKit", "UIKit", "SwiftUI", "CoreGraphics", "UniformTypeIdentifiers", "CoreText", "Cocoa"]
        let files = try FileManager.default.contentsOfDirectory(atPath: Self.sources.path).filter { $0.hasSuffix(".swift") }
        #expect(files.count >= 10)
        for file in files {
            let lines = try String(contentsOf: Self.sources.appendingPathComponent(file), encoding: .utf8).components(separatedBy: "\n")
            var guardedBy: [String] = []
            for line in lines {
                let text = line.trimmingCharacters(in: .whitespaces)
                if text.hasPrefix("#if canImport(") { guardedBy.append(text.components(separatedBy: " &&").first ?? text) }
                if text.hasPrefix("#endif"), !guardedBy.isEmpty { guardedBy.removeLast() }
                guard text.hasPrefix("import ") else { continue }
                let module = String(text.dropFirst("import ".count))
                if forbidden.contains(module) {
                    #expect(guardedBy.contains("#if canImport(\(module))"), "\(file) importe \(module) sans repli")
                }
            }
        }
    }

    @Test("Mesure du texte sans police : jamais plus petite que la vraie, à 10 % près au plus grand")
    func estimationDuTexte() {
        for (text, size, weight) in [("Commander", CGFloat(11.5), FontWeight.medium), ("0,N  enfant", 11, .bold), ("1..*", 11, .semibold),
                                     ("PersonneAvecUnNomTresLong", 13, .semibold),
                                     ("Élève", 12, .regular), ("+ id_client", 13, .semibold), ("0,1  epouse", 11, .bold), ("Coordonner", 11.5, .medium)] {
            let estimate = TextMetrics.estimated(text, size: size, weight: weight)
            let real = TextMetrics.size(text, size: size, weight: weight)
            #expect(estimate.width >= real.width, "« \(text) » estimé trop étroit")
            #expect(estimate.width <= real.width * 1.10 + 3, "« \(text) » estimé beaucoup trop large")
            #expect(estimate.height >= real.height - 1)
        }
    }

    @Test("Fichier .mcd : lu même précédé d'espaces ou d'une marque UTF-8 (fichiers venant de Windows)")
    func lectureTolerante() throws {
        let json = try ModelFile.encode(.exemple)
        for prefix in [Data(), Data("\n  ".utf8), Data([0xEF, 0xBB, 0xBF]), Data([0xEF, 0xBB, 0xBF] + Array("\r\n".utf8))] {
            let model = try ModelFile.read(prefix + json)
            #expect(model.entities.count == MCDModel.exemple.entities.count)
        }
        #expect(throws: ModelFile.Failure.self) { try ModelFile.read(Data()) }
        #expect(throws: ModelFile.Failure.self) { try ModelFile.read(Data(#"{"entities": 3}"#.utf8)) }
    }

    @Test("Le format .mcd est stable : enregistrer deux fois donne exactement les mêmes octets")
    func formatStable() throws {
        let once = try ModelFile.encode(.exempleScolarite)
        let twice = try ModelFile.encode(try ModelFile.read(once))
        #expect(once == twice)
    }
}
