import Testing
import Foundation
#if SWIFT_PACKAGE
@testable import CardinalCore
#else
@testable import Cardinal
#endif

@Suite("SGBD personnalisé")
struct CustomDialectTests {
    @Test("Les paramètres {n}, {p}, {s} sont remplacés")
    func parametres() {
        let custom = CustomDialect(types: ["varchar": "CHARACTER VARYING({n})", "decimal": "NUMBER({p}, {s})"])
        #expect(custom.render(TypeSpec(kind: .varchar, length: 80)) == "CHARACTER VARYING(80)")
        #expect(custom.render(TypeSpec(kind: .decimal, precision: 12, scale: 3)) == "NUMBER(12, 3)")
        #expect(custom.render(TypeSpec(kind: .entier)) == nil) // non personnalisé : SGBD de base
    }

    @Test("Un texte saisi ne peut pas casser le script", arguments: [
        ("TEXT;", "TEXT"), ("INT,\n", "INT"), ("   ", nil), ("BIG INT ; DROP TABLE x", "BIG INT  DROP TABLE x"),
    ])
    func nettoyage(saisie: String, attendu: String?) {
        let custom = CustomDialect(types: ["int": saisie])
        #expect(custom.render(TypeSpec(kind: .entier)) == attendu.map { $0 })
    }

    @Test("Le script utilise les types personnalisés et le SGBD de base pour le reste")
    func script() {
        let custom = CustomDialect(name: "Mon SQLite", base: .sqlite, types: ["varchar": "VARCHAR({n})", "date": "DATETEXT"])
        let sql = SQLGenerator.script(for: .exemple, custom: custom)
        #expect(sql.contains("-- SGBD : Mon SQLite (personnalisé, basé sur SQLite)"))
        #expect(sql.contains("nom VARCHAR(60)"))
        #expect(sql.contains("date_commande DATETEXT"))
        #expect(sql.contains("id_client INTEGER")) // type non personnalisé : celui de SQLite
        #expect(runSQLite(sql) == nil) // et le script s'exécute
        // Hors de ce script, rien ne reste personnalisé.
        #expect(!SQLGenerator.script(for: .exemple, dialect: .sqlite).contains("DATETEXT"))
    }

    @Test("Réglage enregistré et relu à l'identique")
    func enregistrement() throws {
        let custom = CustomDialect(name: "Access", base: .sqlserver, types: ["boolean": "YESNO", "counter": "AUTOINCREMENT"])
        #expect(try JSONDecoder().decode(CustomDialect.self, from: JSONEncoder().encode(custom)) == custom)
    }
}
