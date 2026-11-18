import AppKit
import CoreGraphics

// Générateur de l'icône de Cardinal (variante 1 retenue).
// Usage : swiftc -O icone.swift -o icone && ./icone 1 1024 icone.png   (ou ./icone board planche.png)
// Icône de Cardinal : un mini MCD (deux entités reliées par une association), dans la grille
// standard des icônes macOS (forme de 824 px sur un canevas de 1024, ombre portée).
func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func squircle(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// Forme des icônes macOS : superellipse (coins continus, sans cassure de courbure).
func appShape(_ rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    let n: CGFloat = 5
    let a = rect.width / 2, b = rect.height / 2
    for i in 0...360 {
        let t = CGFloat(i) * .pi / 180
        let c = cos(t), s = sin(t)
        let x = rect.midX + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = rect.midY + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

/// Texte centré (repère retourné : origine en haut à gauche).
func drawText(_ ctx: CGContext, _ text: String, center: CGPoint, size: CGFloat, color: CGColor) {
    let font = NSFont.systemFont(ofSize: size, weight: .heavy)
    let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor(cgColor: color)!])
    let line = CTLineCreateWithAttributedString(attributed)
    var ascent: CGFloat = 0, descent: CGFloat = 0
    let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
    ctx.saveGState()
    ctx.textMatrix = .identity
    // Repère retourné : on place la ligne de base pour centrer la hauteur des capitales.
    ctx.translateBy(x: center.x - width / 2, y: center.y + (ascent - descent) / 2 - 2)
    ctx.scaleBy(x: 1, y: -1)
    ctx.textPosition = .zero
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

/// Dessine dans un repère 1024 × 1024, origine en haut à gauche.
func draw(_ ctx: CGContext, variant: Int, pixels: CGFloat) {
    let small = pixels <= 64
    ctx.saveGState()
    ctx.translateBy(x: 0, y: pixels)
    ctx.scaleBy(x: pixels / 1024, y: -pixels / 1024)

    // Fond : bleu profond, léger dégradé vertical, ombre portée sous la forme.
    let shape = CGRect(x: 100, y: 100, width: 824, height: 824)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * 1), blur: 20, color: rgb(0x000000, 0.35))
    ctx.addPath(squircle(shape, 186)); ctx.setFillColor(rgb(0x173463)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(squircle(shape, 186)); ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [rgb(0x2A5BA8), rgb(0x142B55)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    // Reflet fin en haut : la lumière accroche le bord.
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.18)); ctx.setLineWidth(4)
    ctx.addPath(squircle(shape.insetBy(dx: 2, dy: 2), 184)); ctx.strokePath()
    ctx.restoreGState()

    // Composition.
    let cardSize = CGSize(width: 286, height: 214)
    let capsuleSize = CGSize(width: 252, height: 104)
    let cards: [CGRect]
    let capsuleCenter: CGPoint
    if variant == 0 {
        cards = [CGRect(x: 190, y: 196, width: cardSize.width, height: cardSize.height),
                 CGRect(x: 548, y: 614, width: cardSize.width, height: cardSize.height)]
        capsuleCenter = CGPoint(x: 512, y: 512)
    } else {
        cards = [CGRect(x: 172, y: 256, width: 300, height: 226),
                 CGRect(x: 552, y: 256, width: 300, height: 226)]
        capsuleCenter = CGPoint(x: 512, y: 714)
    }
    let capsule = CGRect(x: capsuleCenter.x - capsuleSize.width / 2, y: capsuleCenter.y - capsuleSize.height / 2,
                         width: capsuleSize.width, height: capsuleSize.height)

    // Pattes (sous les formes).
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.85)); ctx.setLineWidth(small ? 22 : 14); ctx.setLineCap(.round)
    for card in cards {
        ctx.move(to: CGPoint(x: card.midX, y: card.midY)); ctx.addLine(to: capsuleCenter); ctx.strokePath()
    }

    // Cardinalités sur les pattes (lisibles à partir de 128 px seulement).
    if pixels >= 256 && variant == 1 {
        for (card, text) in zip(cards, ["1,N", "0,N"]) {
            let start = CGPoint(x: card.midX, y: card.maxY)
            let point = CGPoint(x: start.x + (capsuleCenter.x - start.x) * 0.42, y: start.y + (capsuleCenter.y - start.y) * 0.42)
            let pill = CGRect(x: point.x - 58, y: point.y - 29, width: 116, height: 58)
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 10, color: rgb(0x000000, 0.25))
            ctx.addPath(squircle(pill, 30)); ctx.setFillColor(rgb(0xFFFFFF)); ctx.fillPath()
            ctx.restoreGState()
            drawText(ctx, text, center: point, size: 40, color: rgb(0xB06A0A))
        }
    }

    // Entités : carte blanche, en-tête bleu, lignes de propriétés, clé ambre sur l'identifiant.
    for card in cards {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: rgb(0x000000, 0.30))
        ctx.addPath(squircle(card, 34)); ctx.setFillColor(rgb(0xFFFFFF)); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(squircle(card, 34)); ctx.clip()
        ctx.setFillColor(rgb(0x2F66C2)); ctx.fill(CGRect(x: card.minX, y: card.minY, width: card.width, height: 66))
        ctx.restoreGState()
        if !small {
            let left = card.minX + 34
            for (index, width) in [CGFloat(150), 196, 128].enumerated() {
                let y = card.minY + 100 + CGFloat(index) * 36
                let x = index == 0 ? left + 34 : left
                ctx.addPath(squircle(CGRect(x: x, y: y, width: width, height: 16), 8))
                ctx.setFillColor(index == 0 ? rgb(0x1F3E73) : rgb(0xB9C6DA)); ctx.fillPath()
            }
            ctx.addEllipse(in: CGRect(x: left, y: card.minY + 98, width: 20, height: 20))
            ctx.setFillColor(rgb(0xF2A93B)); ctx.fillPath()
        }
    }

    // Association : capsule ambre, bord clair.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: rgb(0x000000, 0.30))
    ctx.addPath(squircle(capsule, capsuleSize.height / 2)); ctx.setFillColor(rgb(0xF2A93B)); ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(squircle(capsule.insetBy(dx: 3, dy: 3), capsuleSize.height / 2 - 3))
    ctx.setStrokeColor(rgb(0xFFE2A8, 0.9)); ctx.setLineWidth(5); ctx.strokePath()
    if !small {
        ctx.addPath(squircle(CGRect(x: capsuleCenter.x - 70, y: capsuleCenter.y - 9, width: 140, height: 18), 9))
        ctx.setFillColor(rgb(0x7A4A08, 0.85)); ctx.fillPath()
    }
    ctx.restoreGState()
}

func render(variant: Int, pixels: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    draw(ctx, variant: variant, pixels: CGFloat(pixels))
    return ctx.makeImage()!
}

func save(_ image: CGImage, _ path: String) {
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let args = CommandLine.arguments
if args.count > 1 && args[1] == "board" {
    // Planche : chaque variante à 16, 32, 64, 128, 256 px (taille réelle), fonds clair et sombre.
    let sizes = [16, 32, 64, 128, 256]
    let width = 40 + sizes.reduce(0) { $0 + $1 + 30 }
    let height = 2 * (256 + 40) * 2
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    for (row, (variant, background)) in [(0, 0xF2F2F5), (0, 0x1E1E1E), (1, 0xF2F2F5), (1, 0x1E1E1E)].enumerated() {
        let top = CGFloat(height - (row + 1) * 296)
        ctx.setFillColor(rgb(UInt32(background))); ctx.fill(CGRect(x: 0, y: top, width: CGFloat(width), height: 296))
        var x: CGFloat = 20
        for size in sizes {
            ctx.draw(render(variant: variant, pixels: size), in: CGRect(x: x, y: top + 20, width: CGFloat(size), height: CGFloat(size)))
            x += CGFloat(size) + 30
        }
    }
    save(ctx.makeImage()!, args[2])
} else if args.count > 3 {
    save(render(variant: Int(args[1])!, pixels: Int(args[2])!), args[3])
}
