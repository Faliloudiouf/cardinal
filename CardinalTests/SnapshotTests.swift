import AppKit
import SwiftUI
import Testing
@testable import Cardinal

/// Dessine les écrans de l'appli dans des fichiers PNG, sans capture d'écran système.
/// Ne s'exécute que si la variable d'environnement SNAPSHOT_DIR est définie.
@MainActor
@Suite("Captures")
struct SnapshotTests {
    @Test("Écrans en clair et en sombre")
    func captures() throws {
        guard let directory = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] else { return }
        let scolarite = MCDModel.exempleScolarite
        let cases: [(String, MCDModel, ViewMode, Set<NodeRef>)] = [
            ("mcd", scolarite, .mcd, []),
            ("mcd_heritage", scolarite, .mcd, [.inheritance(scolarite.inheritances[0].id)]),
            ("mcd_multi", scolarite, .mcd, [.entity(scolarite.entities[3].id), .entity(scolarite.entities[4].id)]),
            ("mcd_cif", scolarite, .mcd, [.constraint(scolarite.constraints[0].id)]),
            ("mld", scolarite, .mld, []),
            ("uml", scolarite, .uml, []),
            ("sql", scolarite, .sql, []),
        ]
        for (theme, appearance) in [("clair", NSAppearance.Name.aqua), ("sombre", NSAppearance.Name.darkAqua)] {
            for (name, model, mode, selection) in cases {
                let view = ContentView(
                    document: .constant(CardinalDocument(model: model)),
                    initialMode: mode,
                    initialSelection: selection
                )
                try render(view, appearance: appearance, to: URL(fileURLWithPath: directory).appendingPathComponent("\(name)_\(theme).png"))
            }
        }
        // Planche des miniatures du ruban, en taille réelle, clair et sombre.
        let glyphs: [(Glyph, String)] = [
            (.formalismMCD, "E/A"), (.formalismMLD, "MLD"), (.formalismUML, "UML"), (.formalismSQL, "SQL"),
            (.entity, "Entité"), (.association, "Association"), (.inheritance, "Héritage"), (.constraint, "Contrainte"),
            (.cif, "CIF"), (.rule, "Règle"), (.link, "Lien"), (.text, "Texte"),
        ]
        let board = HStack(spacing: 18) {
            ForEach(Array(glyphs.enumerated()), id: \.offset) { _, item in
                VStack(spacing: 6) {
                    GlyphView(glyph: item.0)
                    Text(item.1).font(.system(size: 11))
                }
            }
        }
        .padding(24)
        .frame(width: 900, height: 110)
        .background(Color(nsColor: .windowBackgroundColor))
        for (theme, appearance) in [("clair", NSAppearance.Name.aqua), ("sombre", NSAppearance.Name.darkAqua)] {
            try render(board, appearance: appearance, size: CGSize(width: 900, height: 110),
                       to: URL(fileURLWithPath: directory).appendingPathComponent("planche_\(theme).png"))
            try render(ContentView(document: .constant(CardinalDocument(model: .exemple))), appearance: appearance,
                       to: URL(fileURLWithPath: directory).appendingPathComponent("ruban_\(theme).png"))
        }

        // Fichier Looping réel ouvert dans Cardinal.
        let looURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../Core/Tests/CardinalCoreTests/Fixtures/LoopingEntrepriseServices2.loo")
        let loo = try LooImporter.model(from: Data(contentsOf: looURL))
        for (name, mode) in [("loo_mcd", ViewMode.mcd), ("loo_mld", ViewMode.mld), ("loo_uml", ViewMode.uml), ("loo_sql", ViewMode.sql)] {
            try render(ContentView(document: .constant(CardinalDocument(model: loo)), initialMode: mode),
                       appearance: .aqua, to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
        }
        if let png = Exporter.pngData(loo) {
            try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("export_loo.png"))
        }
        // Cassures de pattes, flèches de dépendance, poignées sur l'association sélectionnée.
        var bent = MCDModel.exemple
        bent.settings.showDependencies = true
        for index in bent.associations.indices {
            if let leg = bent.associations[index].legs.first { bent.toggleBend(association: bent.associations[index].id, leg: leg.id) }
        }
        try render(ContentView(document: .constant(CardinalDocument(model: bent)), initialSelection: [.association(bent.associations[0].id)]),
                   appearance: .aqua, to: URL(fileURLWithPath: directory).appendingPathComponent("mcd_cassures.png"))

        // Illustrations : cadre rempli, ellipse, flèche (sélectionnée : poignées d'extrémités), image.
        var illustrated = MCDModel.exemple
        var frameFigure = Figure(kind: .rectangle, position: CGPoint(x: 500, y: 330), isFilled: true)
        frameFigure.size = CGSize(width: 760, height: 330)
        frameFigure.color = .sarcelle
        var arrowFigure = Figure(kind: .arrow, position: .zero)
        arrowFigure.setEnds(CGPoint(x: 220, y: 560), CGPoint(x: 330, y: 300))
        arrowFigure.color = .rouge
        var ellipseFigure = Figure(kind: .ellipse, position: CGPoint(x: 1100, y: 620))
        ellipseFigure.color = .violet
        var imageFigure = Figure(kind: .image, position: CGPoint(x: 160, y: 620))
        imageFigure.size = CGSize(width: 96, height: 96)
        imageFigure.imageData = NSApp?.applicationIconImage.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }
        illustrated.figures = [frameFigure, arrowFigure, ellipseFigure, imageFigure]
        try render(ContentView(document: .constant(CardinalDocument(model: illustrated)), initialSelection: [.figure(arrowFigure.id)]),
                   appearance: .aqua, to: URL(fileURLWithPath: directory).appendingPathComponent("mcd_illustrations.png"))

        // Ruban adaptatif : large, moyen (boutons compacts), étroit.
        for width in [1900, 1440, 1300] {
            try render(ContentView(document: .constant(CardinalDocument(model: .exemple))), appearance: .aqua,
                       size: CGSize(width: CGFloat(width), height: 700),
                       to: URL(fileURLWithPath: directory).appendingPathComponent("ruban_\(width).png"))
        }

        // Vues : « Commandes » ne montre que Client, Commande et Passer.
        var withViews = MCDModel.exemple
        let commandes = ModelView(name: "Commandes", refs: Array(withViews.completed([.entity(withViews.entities[0].id), .entity(withViews.entities[1].id)])))
        withViews.views = [commandes, ModelView(name: "Catalogue", refs: [.entity(withViews.entities[2].id)])]
        try render(ContentView(document: .constant(CardinalDocument(model: withViews)), initialView: commandes.id),
                   appearance: .aqua, to: URL(fileURLWithPath: directory).appendingPathComponent("mcd_vues.png"))

        // Onglet « SGBD personnalisé ».
        try render(CustomDialectSettings(), appearance: .aqua, size: CGSize(width: 580, height: 480),
                   to: URL(fileURLWithPath: directory).appendingPathComponent("sgbd_personnalise.png"))

        // Réglages (onglet Général, avec l'apparence).
        for (theme, appearance) in [("clair", NSAppearance.Name.aqua), ("sombre", NSAppearance.Name.darkAqua)] {
            try render(SettingsView(), appearance: appearance, size: CGSize(width: 540, height: 400),
                       to: URL(fileURLWithPath: directory).appendingPathComponent("reglages_\(theme).png"))
        }

        // Fenêtre d'accueil : vide, puis avec des récents aux noms très longs.
        let longFolder = "/private/tmp/claude-501/essai/Un dossier au nom vraiment très long pour voir comment le chemin se coupe/"
        let recents = [URL(fileURLWithPath: "/private/tmp/claude-501/essai/Gestion des commandes.mcd"),
                       URL(fileURLWithPath: longFolder + "Modèle de la gestion des inscriptions et des examens de l'ESP de Dakar.mcd")]
        for (theme, appearance) in [("clair", NSAppearance.Name.aqua), ("sombre", NSAppearance.Name.darkAqua)] {
            try render(WelcomeView(previewRecents: recents), appearance: appearance, size: CGSize(width: 840, height: 520),
                       to: URL(fileURLWithPath: directory).appendingPathComponent("accueil_\(theme).png"))
        }
        try render(WelcomeView(previewRecents: []), appearance: .aqua, size: CGSize(width: 840, height: 520),
                   to: URL(fileURLWithPath: directory).appendingPathComponent("accueil_vide.png"))

        // Fenêtre « Propriété » (types façon Looping), plusieurs familles de types.
        let editors: [(String, Attribute)] = [
            ("propriete_texte", Attribute(name: "prenom_client", type: .varchar, length: 50, label: "Prénom du client")),
            ("propriete_decimal", Attribute(name: "prix", type: .decimal, precision: 10, scale: 2, isNotNull: true, complement: "DEFAULT 0")),
            ("propriete_enum", Attribute(name: "statut", type: .enumeration, enumValues: ["actif", "suspendu", "clos"])),
            ("propriete_compteur", Attribute(name: "id_client", type: .compteur, isIdentifier: true)),
        ]
        for (name, attribute) in editors {
            for (theme, appearance) in [("clair", NSAppearance.Name.aqua), ("sombre", NSAppearance.Name.darkAqua)] {
                try render(AttributeEditor(attribute: attribute, allowsIdentifier: true, tint: Theme.entity) { _ in },
                           appearance: appearance, size: CGSize(width: 560, height: 720),
                           to: URL(fileURLWithPath: directory).appendingPathComponent("\(name)_\(theme).png"))
            }
        }
        var typed = MCDModel.exemple
        typed.entities[0].attributes[0].type = .compteur
        try render(ContentView(document: .constant(CardinalDocument(model: typed)), initialSelection: [.entity(typed.entities[0].id)]),
                   appearance: .aqua, to: URL(fileURLWithPath: directory).appendingPathComponent("inspecteur_types.png"))

        // Cas extrêmes de lisibilité (mêmes modèles que les tests de lisibilité).
        for (name, model) in [("charge", ReadabilityModels.charge(spacing: 520)), ("serre", ReadabilityModels.charge(spacing: 120)), ("empile", ReadabilityModels.charge(spacing: 0))] {
            try render(UMLDiagram(model: model, simplified: false).fixedSize().padding(1), appearance: .aqua, size: UMLLayout(model: model, simplified: false).size,
                       to: URL(fileURLWithPath: directory).appendingPathComponent("lisib_uml_\(name).png"))
            let tables = MLDBuilder.build(model)
            try render(MLDDiagram(model: model, tables: tables, crowsFoot: false), appearance: .aqua, size: MLDLayout.layout(model: model, tables: tables).size,
                       to: URL(fileURLWithPath: directory).appendingPathComponent("lisib_mld_\(name).png"))
        }
        let chargeMCD = ReadabilityModels.charge(spacing: 520)
        try render(ContentView(document: .constant(CardinalDocument(model: chargeMCD))), appearance: .aqua, size: CGSize(width: 2300, height: 1300),
                   to: URL(fileURLWithPath: directory).appendingPathComponent("lisib_mcd_charge.png"))
        try render(UMLDiagram(model: scolarite, simplified: false), appearance: .aqua, size: UMLLayout(model: scolarite, simplified: false).size,
                   to: URL(fileURLWithPath: directory).appendingPathComponent("lisib_uml_scolarite.png"))
        // MLD graphique en pattes de corbeau.
        UserDefaults.standard.set(MLDDisplay.crowsFoot.rawValue, forKey: "affichageMLD")
        defer { UserDefaults.standard.removeObject(forKey: "affichageMLD") }
        try render(
            ContentView(document: .constant(CardinalDocument(model: scolarite)), initialMode: .mld),
            appearance: .aqua,
            to: URL(fileURLWithPath: directory).appendingPathComponent("mld_corbeau_clair.png")
        )
        // Export PNG tel que produit par le menu Exporter.
        if let png = Exporter.pngData(scolarite) {
            try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("export_scolarite.png"))
        }
    }

    private func render(_ view: some View, appearance: NSAppearance.Name, size: CGSize = CGSize(width: 1500, height: 960), to url: URL) throws {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        window.orderBack(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))

        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let data = try #require(rep.representation(using: .png, properties: [:]))
        try data.write(to: url)
        window.orderOut(nil)
    }
}
