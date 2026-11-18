import Foundation

// Requêtes de l'interface Windows / Linux vers le moteur. Chaque requête est un objet JSON
// { "op": "...", ... } ; la réponse est { "ok": ... } ou { "erreur": "message lisible" }.
// Le moteur reste la seule source de vérité : l'interface ne recalcule ni MLD, ni SQL, ni tracés.

enum Requetes {
    struct Enveloppe: Decodable { let op: String }

    struct Echec: Error { let message: String }

    static func traiter(_ octets: [UInt8]) -> [UInt8] {
        let data = Data(octets)
        let decodeur = JSONDecoder()
        do {
            let op = try decodeur.decode(Enveloppe.self, from: data).op
            let resultat = try executer(op, data, decodeur)
            return Array(resultat)
        } catch let echec as Echec {
            return erreur(echec.message)
        } catch let echec as LocalizedError {
            return erreur(echec.errorDescription ?? "\(echec)")
        } catch {
            return erreur("Requête illisible : \(error)")
        }
    }

    private static func erreur(_ message: String) -> [UInt8] {
        Array((try? JSONEncoder().encode(["erreur": message])) ?? Data(#"{"erreur":"?"}"#.utf8))
    }

    private static func ok<T: Encodable>(_ valeur: T) throws -> Data {
        try JSONEncoder().encode(Reponse(ok: valeur))
    }

    struct Reponse<T: Encodable>: Encodable { let ok: T }

    // MARK: Aiguillage

    private static func executer(_ op: String, _ data: Data, _ d: JSONDecoder) throws -> Data {
        switch op {
        case "version":
            return try ok("0.1.0")
        case "exemple":
            struct R: Decodable { let nom: String? }
            let nom = try d.decode(R.self, from: data).nom
            return try ok(nom == "scolarite" ? MCDModel.exempleScolarite : MCDModel.exemple)
        case "vide":
            return try ok(MCDModel())
        case "lire":
            // Contenu en base64 : un .loo n'est pas forcément de l'UTF-8.
            struct R: Decodable { let base64: String; let looping: Bool? }
            let r = try d.decode(R.self, from: data)
            guard let contenu = Data(base64Encoded: r.base64) else { throw Echec(message: "Le fichier n'a pas pu être lu.") }
            return try ok(try ModelFile.read(contenu, isLooping: r.looping ?? false))
        case "encoder":
            struct R: Decodable { let modele: MCDModel }
            let modele = try d.decode(R.self, from: data).modele
            return try ok(String(decoding: try ModelFile.encode(modele), as: UTF8.self))
        case "dessin":
            struct R: Decodable { let modele: MCDModel; let vue: UUID? }
            let r = try d.decode(R.self, from: data)
            return try ok(Dessin(r.modele.visible(in: r.vue)))
        case "verifier":
            struct R: Decodable { let modele: MCDModel }
            let modele = try d.decode(R.self, from: data).modele
            return try ok(Validator.check(modele).map(DiagnosticJS.init))
        case "mld":
            struct R: Decodable { let modele: MCDModel }
            return try ok(MLDJS(try d.decode(R.self, from: data).modele))
        case "uml":
            struct R: Decodable { let modele: MCDModel; let simplifie: Bool? }
            let r = try d.decode(R.self, from: data)
            return try ok(UMLJS(UMLLayout(model: r.modele, simplified: r.simplifie ?? false)))
        case "sql":
            struct R: Decodable { let modele: MCDModel; let sgbd: String?; let perso: CustomDialect? }
            let r = try d.decode(R.self, from: data)
            if let perso = r.perso { return try ok(SQLGenerator.script(for: r.modele, custom: perso)) }
            let sgbd = SQLDialect(rawValue: r.sgbd ?? "") ?? .postgresql
            return try ok(SQLGenerator.script(for: r.modele, dialect: sgbd))
        case "xml":
            struct R: Decodable { let modele: MCDModel }
            return try ok(MLDXMLExporter.xml(MLDBuilder.build(try d.decode(R.self, from: data).modele)))
        case "retro":
            struct R: Decodable { let sql: String }
            return try ok(try ReverseEngineer.model(from: try d.decode(R.self, from: data).sql))
        case "types":
            return try ok(TypeInfo.catalogue)
        case "attribut":
            return try attribut(data, d)
        case "modifier":
            return try modifier(data, d)
        default:
            throw Echec(message: "Opération inconnue : \(op)")
        }
    }

    // MARK: Propriétés

    /// Changement de type (règles du moteur), aperçu SQL par SGBD et problèmes détectés.
    private static func attribut(_ data: Data, _ d: JSONDecoder) throws -> Data {
        struct R: Decodable { let attribut: Attribute; let type: String?; let normaliser: Bool? }
        struct Sortie: Encodable {
            let attribut: Attribute
            let affichage: String
            let apercu: [String: String]
            let problemes: [Probleme]
        }
        struct Probleme: Encodable { let texte: String; let erreur: Bool }
        let r = try d.decode(R.self, from: data)
        var attribut = r.attribut
        if let brut = r.type, let type = DataType(rawValue: brut) { attribut.setType(type) }
        if r.normaliser == true {
            attribut.name = attribut.name.trimmingCharacters(in: .whitespacesAndNewlines)
            attribut.spec = attribut.spec.normalized
            if attribut.isIdentifier { attribut.isNotNull = false; attribut.isUnique = false }
        }
        var apercu: [String: String] = [:]
        for dialect in SQLDialect.allCases { apercu[dialect.rawValue] = definition(attribut, dialect) }
        return try ok(Sortie(attribut: attribut, affichage: attribut.spec.display, apercu: apercu,
                             problemes: Validator.typeProblems([attribut]).map { Probleme(texte: $0.text, erreur: $0.isError) }))
    }

    private static func definition(_ attribut: Attribute, _ dialect: SQLDialect) -> String {
        let column = MLDColumn(name: attribut.name.isEmpty ? "colonne" : attribut.name.sqlIdentifier, spec: attribut.spec,
                               isPrimaryKey: attribut.isIdentifier, isNullable: !attribut.isNotNull && !attribut.isIdentifier,
                               isUnique: attribut.isUnique)
        var pieces = [SQLGenerator.sqlType(column, dialect: dialect)]
        if let collate = SQLGenerator.collation(column.spec, dialect: dialect) { pieces.append(collate) }
        let table = MLDTable(name: "t", columns: [column], comesFromAssociation: false)
        if let identity = SQLGenerator.identityClause(column, in: table, dialect: dialect) { pieces.append(identity) }
        if dialect == .sqlite, attribut.type == .compteur, attribut.isIdentifier { pieces.append("PRIMARY KEY AUTOINCREMENT") }
        if let check = SQLGenerator.check(column, dialect: dialect) { pieces.append(check) }
        return pieces.joined(separator: " ")
    }

    // MARK: Modifications qui ont des règles (le reste se fait directement dans l'interface)

    private static func modifier(_ data: Data, _ d: JSONDecoder) throws -> Data {
        struct R: Decodable {
            let modele: MCDModel
            let action: String
            let refs: [NodeRef]?
            let dx: Double?
            let dy: Double?
            let association: UUID?
            let patte: UUID?
            let fragment: MCDModel?
            let base: String?
        }
        struct Sortie: Encodable { let modele: MCDModel; let refs: [NodeRef] }
        let r = try d.decode(R.self, from: data)
        var modele = r.modele
        var refs: [NodeRef] = []
        switch r.action {
        case "supprimer":
            for ref in r.refs ?? [] { modele.remove(ref) }
        case "deplacer":
            modele.move(Set(r.refs ?? []), by: CGSize(width: r.dx ?? 0, height: r.dy ?? 0))
        case "cassure":
            if let a = r.association, let p = r.patte { modele.toggleBend(association: a, leg: p) }
        case "copier":
            let choix = modele.completed(Set(r.refs ?? []))
            return try ok(Sortie(modele: modele.subset(choix), refs: Array(choix)))
        case "coller":
            if let fragment = r.fragment { refs = Array(modele.paste(fragment)) }
        case "completer":
            refs = Array(modele.completed(Set(r.refs ?? [])))
        case "nom":
            // Renvoie seulement un nom libre, dans `refs` vide ; le nom est placé dans `modele` inchangé.
            struct Nom: Encodable { let nom: String }
            return try ok(Nom(nom: modele.uniqueName(base: r.base ?? "Entité")))
        default:
            throw Echec(message: "Modification inconnue : \(r.action)")
        }
        return try ok(Sortie(modele: modele, refs: refs))
    }
}

// MARK: - Formes envoyées à l'interface

struct P: Encodable {
    let x: Double, y: Double
    init(_ p: CGPoint) { x = Double(p.x); y = Double(p.y) }
}

struct R4: Encodable {
    let x: Double, y: Double, w: Double, h: Double
    init(_ r: CGRect) { x = Double(r.minX); y = Double(r.minY); w = Double(r.width); h = Double(r.height) }
}

/// Tout ce qu'il faut pour dessiner le MCD : cadres, pattes, cardinalités, ports des autres liens.
struct Dessin: Encodable {
    struct Noeud: Encodable { let ref: NodeRef; let cadre: R4 }
    struct Patte: Encodable { let association: UUID; let patte: Int; let points: [P]; let maxUn: Bool }
    struct Etiquette: Encodable { let texte: String; let association: UUID; let patte: Int; let ancre: P; let cadre: R4 }
    struct Attribut: Encodable { let id: UUID; let type: String }

    let noeuds: [Noeud]
    let pattes: [Patte]
    let etiquettes: [Etiquette]
    let ports: [String: P]
    let types: [Attribut]
    let limites: R4?

    init(_ modele: MCDModel) {
        noeuds = modele.allRefs.compactMap { ref in NodeMetrics.frame(of: ref, in: modele).map { Noeud(ref: ref, cadre: R4($0)) } }
        let positions = Dictionary(uniqueKeysWithValues: modele.allRefs.compactMap { ref in modele.position(of: ref).map { (ref, $0) } })
        let mise = MCDLabelLayout(model: modele) { positions[$0] ?? .zero }
        pattes = mise.legPaths.map { Patte(association: $0.associationID, patte: $0.legIndex, points: $0.points.map(P.init), maxUn: $0.isMaxOne) }
        etiquettes = mise.labels.map { Etiquette(texte: $0.text, association: $0.associationID, patte: $0.legIndex, ancre: P($0.anchor), cadre: R4($0.frame)) }
        // Clé lisible côté interface : « type:uuid>type:uuid ».
        var ports: [String: P] = [:]
        for (source, cibles) in Self.liens(modele) {
            for cible in cibles {
                if let point = mise.linkPorts[MCDLabelLayout.key(source, cible)] { ports[Self.cle(source) + ">" + Self.cle(cible)] = P(point) }
            }
        }
        self.ports = ports
        types = (modele.entities.flatMap(\.attributes) + modele.associations.flatMap(\.attributes)).map { Attribut(id: $0.id, type: $0.spec.display) }
        limites = NodeMetrics.bounds(of: modele).map(R4.init)
    }

    static func cle(_ ref: NodeRef) -> String {
        switch ref {
        case .entity(let id): "entity:\(id.uuidString)"
        case .association(let id): "association:\(id.uuidString)"
        case .inheritance(let id): "inheritance:\(id.uuidString)"
        case .constraint(let id): "constraint:\(id.uuidString)"
        case .rule(let id): "rule:\(id.uuidString)"
        case .note(let id): "note:\(id.uuidString)"
        case .figure(let id): "figure:\(id.uuidString)"
        }
    }

    static func liens(_ modele: MCDModel) -> [(NodeRef, [NodeRef])] {
        var resultat: [(NodeRef, [NodeRef])] = []
        for h in modele.inheritances {
            resultat.append((.inheritance(h.id), ([h.parentID].compactMap { $0 } + h.childIDs).map { NodeRef.entity($0) }))
        }
        for c in modele.constraints { resultat.append((.constraint(c.id), c.links.map(\.target))) }
        for r in modele.rules { resultat.append((.rule(r.id), r.links)) }
        return resultat
    }
}

struct DiagnosticJS: Encodable {
    let gravite: String
    let message: String
    let cible: NodeRef?
    init(_ d: Diagnostic) {
        gravite = d.severity == .error ? "erreur" : "avertissement"
        message = d.message
        cible = d.target
    }
}

struct MLDJS: Encodable {
    struct Colonne: Encodable {
        let nom: String
        let type: String
        let cle: Bool
        let nulle: Bool
        let unique: Bool
        let reference: String?
    }
    struct Table: Encodable {
        let nom: String
        let colonnes: [Colonne]
        let association: Bool
        let origine: NodeRef?
        let centre: P
        let taille: P
    }
    struct Lien: Encodable { let enfant: String; let parent: String; let points: [P]; let colonnes: [String] }

    let tables: [Table]
    let liens: [Lien]
    let taille: P

    init(_ modele: MCDModel) {
        let tables = MLDBuilder.build(modele)
        let mise = MLDLayout.layout(model: modele, tables: tables)
        self.tables = tables.map { table in
            let taille = MLDLayout.size(of: table)
            return Table(nom: table.name,
                         colonnes: table.columns.map { c in
                             Colonne(nom: c.name, type: c.spec.display, cle: c.isPrimaryKey, nulle: c.isNullable, unique: c.isUnique,
                                     reference: c.reference.map { "\($0.table).\($0.column)" })
                         },
                         association: table.comesFromAssociation, origine: table.origin,
                         centre: P(mise.positions[table.name] ?? .zero), taille: P(CGPoint(x: taille.width, y: taille.height)))
        }
        liens = MLDLayout.links(tables: tables, positions: mise.positions).map {
            Lien(enfant: $0.child, parent: $0.parent, points: $0.points.map(P.init), colonnes: $0.columns.map(\.name))
        }
        taille = P(CGPoint(x: mise.size.width, y: mise.size.height))
    }
}

struct UMLJS: Encodable {
    struct Ligne: Encodable { let texte: String; let identifiant: Bool }
    struct Classe: Encodable { let id: UUID; let nom: String; let lignes: [Ligne]; let cadre: R4; let classeAssociation: Bool }
    struct Trait: Encodable { let points: [P]; let style: String }
    struct Etiquette: Encodable { let texte: String; let genre: String; let cadre: R4 }
    struct Losange: Encodable { let centre: P }

    let classes: [Classe]
    let traits: [Trait]
    let etiquettes: [Etiquette]
    let losanges: [Losange]
    let taille: P

    init(_ uml: UMLLayout) {
        classes = uml.classes.map { Classe(id: $0.id, nom: $0.name, lignes: $0.lines.map { Ligne(texte: $0.text, identifiant: $0.isIdentifier) },
                                           cadre: R4($0.frame), classeAssociation: $0.isAssociationClass) }
        traits = uml.edges.map { edge in
            let style = switch edge.style { case .solid: "plein"; case .dashed: "pointille"; case .generalization: "generalisation" }
            return Trait(points: edge.points.map(P.init), style: style)
        }
        etiquettes = uml.labels.map { label in
            let genre = switch label.kind { case .multiplicity: "multiplicite"; case .role: "role"; case .name: "nom" }
            return Etiquette(texte: label.text, genre: genre, cadre: R4(label.frame))
        }
        losanges = uml.diamonds.map { Losange(centre: P($0.center)) }
        taille = P(CGPoint(x: uml.size.width, y: uml.size.height))
    }
}

/// Catalogue des types, pour construire les menus de l'interface sans dupliquer les règles.
struct TypeInfo: Encodable {
    let id: String
    let categorie: String
    let categorieLibelle: String
    let libelle: String
    let menu: String
    let aide: String
    let encodage: String?
    let stockage: String?
    let longueur: Bool
    let precision: Bool
    let collation: Bool
    let longueurMax: Int

    static var catalogue: [TypeInfo] {
        DataType.allCases.map { t in
            TypeInfo(id: t.rawValue, categorie: t.category.rawValue, categorieLibelle: t.category.label, libelle: t.label,
                     menu: t.menuLabel, aide: t.help, encodage: t.encoding?.rawValue, stockage: t.storage?.rawValue,
                     longueur: t.usesLength, precision: t.usesPrecision, collation: t.usesCollation, longueurMax: t.maxLength)
        }
    }
}
