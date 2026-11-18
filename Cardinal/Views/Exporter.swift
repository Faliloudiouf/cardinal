import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers

/// Exports du diagramme : PNG, PDF, presse-papiers, impression ; et fichiers texte (SQL, XML).
@MainActor
enum Exporter {
    /// Vue du diagramme recadrée sur son contenu, sur fond blanc (pour l'impression et les documents).
    private static func croppedDiagram(_ model: MCDModel) -> some View {
        let bounds = NodeMetrics.bounds(of: model) ?? CGRect(x: 0, y: 0, width: 400, height: 300)
        return DiagramLayer(model: model)
            .frame(width: DiagramView.canvasSize.width, height: DiagramView.canvasSize.height, alignment: .topLeading)
            .offset(x: -bounds.minX, y: -bounds.minY)
            .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
            .clipped()
            .background(Color.white)
            .environment(\.colorScheme, .light)
    }

    /// Le rendu se fait toujours en apparence claire, quel que soit le thème du Mac.
    private static func inLightAppearance<T>(_ work: () -> T) -> T {
        var result: T?
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance { result = work() }
        return result!
    }

    static func pngData(_ model: MCDModel, scale: CGFloat = 2) -> Data? {
        inLightAppearance {
            let renderer = ImageRenderer(content: croppedDiagram(model))
            renderer.scale = scale
            guard let image = renderer.cgImage else { return nil }
            return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        }
    }

    static func pdfData(_ model: MCDModel) -> Data? {
        inLightAppearance {
            let renderer = ImageRenderer(content: croppedDiagram(model))
            let data = NSMutableData()
            renderer.render { size, render in
                var box = CGRect(origin: .zero, size: size)
                guard let consumer = CGDataConsumer(data: data as CFMutableData),
                      let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }
                context.beginPDFPage(nil)
                render(context)
                context.endPDFPage()
                context.closePDF()
            }
            return data.length > 0 ? data as Data : nil
        }
    }

    static func copyDiagram(_ model: MCDModel) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let pdf = pdfData(model) { pasteboard.setData(pdf, forType: .pdf) }
        if let png = pngData(model) { pasteboard.setData(png, forType: .png) }
    }

    static func print(_ model: MCDModel) {
        guard let data = pdfData(model), let document = PDFDocument(data: data) else { return }
        let info = NSPrintInfo.shared
        info.orientation = (NodeMetrics.bounds(of: model)?.width ?? 0) > (NodeMetrics.bounds(of: model)?.height ?? 0) ? .landscape : .portrait
        document.printOperation(for: info, scalingMode: .pageScaleToFit, autoRotate: true)?.run()
    }

    static func save(_ data: Data?, suggestedName: String, type: UTType) {
        guard let data else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    static func savePNG(_ model: MCDModel, name: String) { save(pngData(model), suggestedName: "\(name).png", type: .png) }
    static func savePDF(_ model: MCDModel, name: String) { save(pdfData(model), suggestedName: "\(name).pdf", type: .pdf) }

    static func saveMLDXML(_ model: MCDModel, name: String) {
        save(Data(MLDXMLExporter.xml(MLDBuilder.build(model)).utf8), suggestedName: "\(name)_mld.xml", type: .xml)
    }

    static func saveSQL(_ model: MCDModel, dialect: SQLDialect, name: String) {
        save(Data(SQLTarget.script(for: model, dialect: dialect).utf8),
             suggestedName: "\(name)_\(SQLTarget.name(dialect).sqlIdentifier.lowercased()).sql", type: .sqlScript)
    }

    /// Ouvre un script SQL et le transforme en MCD (rétroconception).
    static func importSQLFile() -> MCDModel? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.sqlScript, .plainText]
        panel.allowsMultipleSelection = false
        panel.message = "Choisissez un script SQL contenant des CREATE TABLE"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            let sql = try String(contentsOf: url, encoding: .utf8)
            return try ReverseEngineer.model(from: sql)
        } catch {
            NSAlert(error: error).runModal()
            return nil
        }
    }

    static func importSQLFromPasteboard() -> MCDModel? {
        guard let sql = NSPasteboard.general.string(forType: .string) else {
            alert("Le presse-papiers ne contient pas de texte.")
            return nil
        }
        do {
            return try ReverseEngineer.model(from: sql)
        } catch {
            NSAlert(error: error).runModal()
            return nil
        }
    }

    static func alert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }
}
