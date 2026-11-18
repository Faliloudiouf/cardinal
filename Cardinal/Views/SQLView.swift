import SwiftUI
import AppKit

struct SQLView: View {
    let model: MCDModel
    let dialect: SQLDialect
    @Binding var zoom: CGFloat

    @State private var zoomAtGestureStart: CGFloat?
    // Le script se régénère dès qu'on change le SGBD personnalisé dans les Réglages.
    @AppStorage(SQLTarget.usesCustomKey) private var usesCustom = false
    @AppStorage(SQLTarget.customKey) private var customData = Data()

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            Text(SQLHighlighter.highlight(SQLTarget.script(for: model, dialect: dialect), size: 12.5 * zoom))
                .font(.system(size: 12.5 * zoom, design: .monospaced))
                .lineSpacing(3 * zoom)
                .textSelection(.enabled)
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .simultaneousGesture(PinchZoom(zoom: $zoom, start: $zoomAtGestureStart).gesture)
    }

    /// Copie le script dans le presse-papiers.
    static func copy(_ model: MCDModel, dialect: SQLDialect) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(SQLTarget.script(for: model, dialect: dialect), forType: .string)
    }
}

/// Pincement au pavé tactile : zoom de 30 % à 250 %.
struct PinchZoom {
    @Binding var zoom: CGFloat
    @Binding var start: CGFloat?

    var gesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let origin = start ?? zoom
                start = origin
                zoom = min(max(origin * value.magnification, 0.3), 2.5)
            }
            .onEnded { _ in start = nil }
    }
}

/// Coloration syntaxique minimale : mots-clés, types et commentaires.
enum SQLHighlighter {
    private static let keywords: Set<String> = [
        "CREATE", "TABLE", "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "CONSTRAINT", "NOT", "NULL", "ENGINE",
        "UNIQUE", "ALTER", "ADD", "CHECK", "TRIGGER", "BEFORE", "AFTER", "INSERT", "UPDATE", "DELETE", "ON", "FOR", "EACH", "ROW",
    ]
    private static let types: Set<String> = [
        "INT", "INTEGER", "NUMBER", "DOUBLE", "PRECISION", "FLOAT", "REAL", "BINARY_DOUBLE", "DECIMAL", "NUMERIC",
        "VARCHAR", "VARCHAR2", "NVARCHAR", "MAX", "TEXT", "CLOB", "DATE", "DATETIME", "DATETIME2", "TIMESTAMP",
        "BOOLEAN", "BIT", "InnoDB",
    ]

    static func highlight(_ script: String, size: CGFloat = 12.5) -> AttributedString {
        var result = AttributedString()
        let lines = script.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() {
            if line.hasPrefix("--") {
                var comment = AttributedString(String(line))
                comment.foregroundColor = .secondary
                result += comment
            } else {
                result += highlightLine(String(line), size: size)
            }
            if index < lines.count - 1 { result += AttributedString("\n") }
        }
        return result
    }

    private static func highlightLine(_ line: String, size: CGFloat) -> AttributedString {
        var result = AttributedString()
        var word = ""

        func flush() {
            guard !word.isEmpty else { return }
            var token = AttributedString(word)
            if keywords.contains(word) {
                token.foregroundColor = Theme.entity
                token.font = .system(size: size, weight: .bold, design: .monospaced)
            } else if types.contains(word) {
                token.foregroundColor = Theme.association
            }
            result += token
            word = ""
        }

        for character in line {
            if character.isLetter || character.isNumber || character == "_" {
                word.append(character)
            } else {
                flush()
                result += AttributedString(String(character))
            }
        }
        flush()
        return result
    }
}
