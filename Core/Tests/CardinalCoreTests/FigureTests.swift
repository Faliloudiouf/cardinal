import Testing
import Foundation
#if SWIFT_PACKAGE
@testable import CardinalCore
#else
@testable import Cardinal
#endif

@Suite("Illustrations : rectangle, ellipse, trait, flèche, image")
struct FigureTests {
    @Test("Trait : extrémités, cadre, inversion du sens")
    func trait() {
        var figure = Figure(kind: .arrow, position: .zero)
        figure.setEnds(CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 200))
        #expect(figure.position == CGPoint(x: 200, y: 150))
        #expect(figure.start == CGPoint(x: 100, y: 100) && figure.end == CGPoint(x: 300, y: 200))
        #expect(figure.frame == CGRect(x: 100, y: 100, width: 200, height: 100))
        figure.setEnds(figure.end, figure.start)
        #expect(figure.start == CGPoint(x: 300, y: 200))
    }

    @Test("Un trait horizontal reste cliquable : cadre d'au moins 16 points de haut")
    func traitPlat() {
        var figure = Figure(kind: .line, position: .zero)
        figure.setEnds(CGPoint(x: 0, y: 50), CGPoint(x: 200, y: 50))
        #expect(figure.frame.height >= Figure.minimumSize)
        #expect(figure.frame.midY == 50)
    }

    @Test("Redimensionner garde le coin opposé fixe et ne descend jamais sous le minimum", arguments: [
        (CGPoint(x: 400, y: 300), CGSize(width: 300, height: 250)),
        (CGPoint(x: 90, y: 40), CGSize(width: 16, height: 16)),
    ])
    func redimensionner(corner: CGPoint, expected: CGSize) {
        var figure = Figure(kind: .rectangle, position: CGPoint(x: 180, y: 100)) // cadre 100…260 × 50…150
        figure.resize(toCorner: corner)
        #expect(figure.size == expected)
        #expect(figure.frame.minX == 100 && figure.frame.minY == 50)
    }

    @Test("Enregistrement : toutes les figures, image comprise ; ancien fichier sans figures lisible")
    func fichier() throws {
        var model = MCDModel.exemple
        var arrow = Figure(kind: .arrow, position: CGPoint(x: 50, y: 50))
        arrow.color = .rouge
        var image = Figure(kind: .image, position: CGPoint(x: 400, y: 400))
        image.imageData = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
        model.figures = [Figure(kind: .rectangle, position: .zero, isFilled: true), arrow, image]
        let back = try ModelFile.read(try ModelFile.encode(model))
        #expect(back.figures == model.figures)
        #expect(try ModelFile.read(Data(#"{"entities":[]}"#.utf8)).figures.isEmpty)
    }

    @Test("Copier-coller, suppression, sélection : une figure se comporte comme les autres éléments")
    func commeLesAutres() {
        var model = MCDModel.exemple
        let figure = Figure(kind: .ellipse, position: CGPoint(x: 900, y: 900))
        model.figures = [figure]
        #expect(model.allRefs.contains(.figure(figure.id)))
        let pasted = model.paste(model.subset([.figure(figure.id)]))
        #expect(model.figures.count == 2)
        #expect(model.figures[1].position == CGPoint(x: 930, y: 930))
        model.remove(pasted.first!)
        #expect(model.figures.count == 1)
        // Aucun effet sur le MLD : mêmes tables, mêmes colonnes.
        func shape(_ m: MCDModel) -> [String] { MLDBuilder.build(m).map { $0.name + ":" + $0.columns.map(\.name).joined(separator: ",") } }
        #expect(shape(model) == shape(.exemple))
    }

    @Test("Coller une association : ses cassures suivent la copie")
    func collerCassures() {
        var model = MCDModel.exemple
        model.associations[0].legs[0].bend = CGPoint(x: 300, y: 100)
        var refs: Set<NodeRef> = [NodeRef.association(model.associations[0].id)]
        for leg in model.associations[0].legs { refs.insert(NodeRef.entity(leg.entityID)) }
        _ = model.paste(model.subset(refs))
        let copy = model.associations.last!
        #expect(copy.legs[0].bend == CGPoint(x: 330, y: 130))
    }

    @Test("Les cardinalités évitent un trait d'illustration, sans le traiter comme une boîte")
    func cardinalitesEtTraits() {
        var model = MCDModel.exemple
        let passer = model.associations[0]
        let client = model.entity(passer.legs[0].entityID)!.position
        var line = Figure(kind: .line, position: .zero)
        line.setEnds(CGPoint(x: client.x + 60, y: client.y - 200), CGPoint(x: client.x + 160, y: client.y + 200))
        model.figures = [line]
        let layout = MCDLabelLayout(model: model) { model.position(of: $0) ?? .zero }
        let segment = Segment(a: line.start, b: line.end)
        for label in layout.labels {
            #expect(!Geometry.intersects(segment, label.frame), "« \(label.text) » posé sur le trait")
        }
        #expect(!layout.obstacles.contains(NodeMetrics.frame(of: .figure(line.id), in: model)!))
    }
}
