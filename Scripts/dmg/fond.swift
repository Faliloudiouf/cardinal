// Fond de la fenêtre d'installation du .dmg (660 × 400 points, en 1x et 2x).
// Identité de Cardinal : bleu institutionnel des entités, ambre des associations, grille de points
// du canevas. Les noms d'icônes sont posés sur une bande de ton moyen (#5F74A5) : Finder les écrit
// en noir (thème clair) ou en blanc (thème sombre), et les deux restent lisibles (contraste ≈ 4,5).
import AppKit

let largeur: CGFloat = 660, hauteur: CGFloat = 400
let version = CommandLine.arguments.dropFirst().first ?? "0.1.0"

func couleur(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

func dessiner(echelle: CGFloat, vers chemin: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(largeur * echelle), pixelsHigh: Int(hauteur * echelle),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: largeur, height: hauteur)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // Repère « haut en haut » : y = 0 en haut de la fenêtre.
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.translateBy(x: 0, y: hauteur); ctx.scaleBy(x: 1, y: -1)

    // Fond : bleu profond vers bleu nuit.
    let degrade = NSGradient(colors: [couleur(0x1E3D70), couleur(0x16294A)])!
    degrade.draw(in: NSRect(x: 0, y: 0, width: largeur, height: hauteur), angle: 90)
    // Grille de points, comme le canevas.
    couleur(0xFFFFFF, 0.07).setFill()
    for x in stride(from: CGFloat(10), to: largeur, by: 20) {
        for y in stride(from: CGFloat(10), to: hauteur, by: 20) {
            NSBezierPath(ovalIn: NSRect(x: x - 0.8, y: y - 0.8, width: 1.6, height: 1.6)).fill()
        }
    }
    // Deux socles (Cardinal, Applications) et, sous chacun, la pastille où Finder écrit le nom :
    // ton moyen, lisible que le nom soit écrit en noir (thème clair) ou en blanc (thème sombre).
    for x in [CGFloat(180), 480] {
        let socle = NSBezierPath(roundedRect: NSRect(x: x - 78, y: 128, width: 156, height: 168), xRadius: 22, yRadius: 22)
        couleur(0xFFFFFF, 0.06).setFill(); socle.fill()
        couleur(0xFFFFFF, 0.12).setStroke(); socle.lineWidth = 1; socle.stroke()
        couleur(0x5F74A5).setFill()
        NSBezierPath(roundedRect: NSRect(x: x - 62, y: 256, width: 124, height: 28), xRadius: 14, yRadius: 14).fill()
    }

    func texte(_ s: String, _ taille: CGFloat, _ graisse: NSFont.Weight, _ c: NSColor, _ y: CGFloat, kern: CGFloat = 0) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: taille, weight: graisse), .foregroundColor: c, .kern: kern]
        let a = NSAttributedString(string: s, attributes: attrs)
        let w = a.size().width
        NSGraphicsContext.saveGraphicsState()
        let t = NSAffineTransform(); t.translateX(by: 0, yBy: hauteur); t.scaleX(by: 1, yBy: -1); t.concat()
        a.draw(at: NSPoint(x: (largeur - w) / 2, y: hauteur - y - a.size().height))
        NSGraphicsContext.restoreGraphicsState()
    }
    texte("Installer Cardinal", 24, .bold, .white, 40, kern: -0.3)
    texte("Glissez Cardinal dans le dossier Applications", 13, .regular, couleur(0xFFFFFF, 0.72), 76)

    // Flèche entre les deux icônes.
    couleur(0xF0B860).setStroke()
    let fleche = NSBezierPath()
    fleche.lineWidth = 3; fleche.lineCapStyle = .round; fleche.lineJoinStyle = .round
    fleche.move(to: NSPoint(x: 280, y: 200)); fleche.line(to: NSPoint(x: 378, y: 200))
    fleche.move(to: NSPoint(x: 366, y: 189)); fleche.line(to: NSPoint(x: 380, y: 200)); fleche.line(to: NSPoint(x: 366, y: 211))
    fleche.stroke()

    texte("Version \(version)  ·  MCD, MLD, UML et SQL  ·  faliloudiouf.com/cardinal", 11, .medium, couleur(0xFFFFFF, 0.5), 352)
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: chemin))
}

dessiner(echelle: 1, vers: "fond.png")
dessiner(echelle: 2, vers: "fond@2x.png")
