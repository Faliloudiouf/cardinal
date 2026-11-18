import SwiftUI

/// État visuel commun à tous les nœuds du diagramme.
struct NodeState: Equatable {
    var isSelected = false
    var isPending = false
    var isLifted = false
}

struct AttributeLine: View {
    let attribute: Attribute
    let tint: Color
    var showsType = true

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "key.fill")
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(tint)
                .opacity(attribute.isIdentifier ? 1 : 0)
                .frame(width: 10)
            Text(attribute.name.isEmpty ? "sans nom" : attribute.name)
                .underline(attribute.isIdentifier)
                .fontWeight(attribute.isIdentifier ? .semibold : .regular)
                .foregroundStyle(attribute.name.isEmpty ? .tertiary : .primary)
            if attribute.isUnique {
                Text("U")
                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .help("Valeur unique")
            }
            Spacer(minLength: 6)
            if showsType {
                Text(attribute.spec.display + (attribute.isNotNull ? " *" : ""))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12))
        .lineLimit(1)
        .frame(height: NodeMetrics.row)
    }
}

/// Bordure, ombre et effet de « soulèvement » communs aux nœuds.
struct NodeChrome<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color
    let state: NodeState
    var dashed = false

    func body(content: Content) -> some View {
        content
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(
                    state.isSelected ? Color.accentColor : tint.opacity(0.6),
                    style: StrokeStyle(lineWidth: state.isSelected ? 2 : 1, dash: dashed && !state.isSelected ? [5, 3] : [])
                )
            }
            .overlay {
                if state.isPending {
                    shape.inset(by: -5)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                }
            }
            .shadow(color: .black.opacity(state.isLifted ? 0.22 : 0.09), radius: state.isLifted ? 14 : 5, y: state.isLifted ? 8 : 2)
            .scaleEffect(state.isLifted ? 1.025 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 1), value: state.isLifted)
    }
}

struct EntityNode: View {
    let entity: Entity
    var settings = ModelSettings()
    var state = NodeState()

    var body: some View {
        let size = NodeMetrics.size(of: entity, settings: settings)
        let fill = entity.color.fill(default: Theme.entityFill)
        let ink = entity.color.ink(default: Theme.entity)
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                Text(entity.name.isEmpty ? "Sans nom" : entity.name)
                    .italic(entity.isFictive)
                if entity.isFictive {
                    Text("fictive")
                        .font(.system(size: 9, weight: .semibold))
                        .textCase(.uppercase)
                        .opacity(0.75)
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .tracking(0.3)
            .foregroundStyle(entity.isFictive ? ink : .white)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: settings.showAttributes ? NodeMetrics.header : size.height)
            .background(entity.isFictive ? AnyShapeStyle(ink.opacity(0.12)) : AnyShapeStyle(fill))

            if settings.showAttributes {
                VStack(alignment: .leading, spacing: 0) {
                    if entity.attributes.isEmpty {
                        Text("Aucune propriété")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .frame(height: NodeMetrics.row)
                    }
                    ForEach(entity.attributes) { AttributeLine(attribute: $0, tint: ink, showsType: settings.showTypes) }
                }
                .padding(.vertical, NodeMetrics.padding)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(Color(nsColor: .textBackgroundColor))
        .modifier(NodeChrome(
            shape: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous),
            tint: ink, state: state, dashed: entity.isFictive
        ))
    }
}

struct AssociationNode: View {
    let association: Association
    var settings = ModelSettings()
    var state = NodeState()

    var body: some View {
        let size = NodeMetrics.size(of: association, settings: settings)
        let ink = association.color.ink(default: Theme.association)
        let isBare = association.attributes.isEmpty || !settings.showAttributes
        let title = Text(association.name.isEmpty ? "Sans nom" : association.name)
            .font(.system(size: 12.5, weight: .semibold))
            .tracking(0.2)
            .foregroundStyle(ink)
            .lineLimit(1)

        Group {
            if isBare {
                title.padding(.horizontal, 14)
            } else {
                VStack(spacing: 0) {
                    title.frame(height: NodeMetrics.header)
                    Rectangle().fill(ink.opacity(0.35)).frame(height: 0.5).padding(.horizontal, 14)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(association.attributes) { AttributeLine(attribute: $0, tint: ink, showsType: settings.showTypes) }
                    }
                    .padding(.vertical, NodeMetrics.padding)
                    .padding(.horizontal, 14)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .background {
            ZStack {
                Color(nsColor: .textBackgroundColor)
                ink.opacity(0.09)
            }
        }
        .modifier(NodeChrome(
            // Pour une capsule parfaite, l'arrondi doit être circulaire (le style continu laisse des bords plats).
            shape: RoundedRectangle(cornerRadius: isBare ? size.height / 2 : 20, style: isBare ? .circular : .continuous),
            tint: ink, state: state
        ))
    }
}

/// Triangle d'héritage, pointe vers le surtype, avec le type de contrainte (X, T, XT).
struct InheritanceNode: View {
    let inheritance: Inheritance
    var state = NodeState()

    var body: some View {
        let size = NodeMetrics.inheritanceSize
        ZStack {
            Triangle().fill(Color(nsColor: .textBackgroundColor))
            Triangle().fill(Theme.entity.opacity(0.12))
            Triangle().stroke(state.isSelected ? Color.accentColor : Theme.entity.opacity(0.8), lineWidth: state.isSelected ? 2 : 1.25)
            Text(inheritance.kind.rawValue.isEmpty ? " " : inheritance.kind.rawValue)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.entity)
                .offset(y: 8)
        }
        .frame(width: size.width, height: size.height)
        .overlay {
            if state.isPending {
                Triangle().stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])).padding(-6)
            }
        }
        .shadow(color: .black.opacity(state.isLifted ? 0.2 : 0.08), radius: state.isLifted ? 10 : 4, y: 2)
        .scaleEffect(state.isLifted ? 1.04 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 1), value: state.isLifted)
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct ConstraintNode: View {
    let constraint: Constraint
    var state = NodeState()

    var body: some View {
        Text(constraint.kind.rawValue)
            .font(.system(size: constraint.kind == .cif ? 11 : 13, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.constraint)
            .frame(width: NodeMetrics.constraintSize.width, height: NodeMetrics.constraintSize.height)
            .background {
                ZStack {
                    Color(nsColor: .textBackgroundColor)
                    Theme.constraint.opacity(0.1)
                }
            }
            .modifier(NodeChrome(shape: Circle(), tint: Theme.constraint, state: state))
    }
}

struct RuleNode: View {
    let rule: Rule
    var state = NodeState()

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: rule.sql.isEmpty ? "r.square.fill" : "curlybraces.square.fill")
                .foregroundStyle(Theme.rule)
            Text(rule.name.isEmpty ? "Règle" : rule.name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(width: NodeMetrics.ruleSize.width, height: NodeMetrics.ruleSize.height)
        .background {
            ZStack {
                Color(nsColor: .textBackgroundColor)
                Theme.rule.opacity(0.1)
            }
        }
        .modifier(NodeChrome(shape: RoundedRectangle(cornerRadius: 7, style: .continuous), tint: Theme.rule, state: state, dashed: true))
    }
}

struct NoteNode: View {
    let note: Note
    var state = NodeState()

    var body: some View {
        let size = NodeMetrics.size(of: note)
        Text(note.text.isEmpty ? "Texte" : note.text)
            .font(note.style == .titre ? .system(size: 20, weight: .bold) : .system(size: 12.5))
            .tracking(note.style == .titre ? -0.3 : 0)
            .foregroundStyle(note.text.isEmpty ? .tertiary : (note.style == .titre ? .primary : .secondary))
            .multilineTextAlignment(.leading)
            .padding(.horizontal, note.style == .titre ? 12 : 10)
            .padding(.vertical, 6)
            .frame(width: size.width, height: size.height, alignment: .leading)
            .background {
                if note.style == .texte {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.04))
                }
            }
            .overlay {
                if state.isSelected || state.isPending {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: state.isSelected ? 2 : 1.5, dash: state.isPending ? [5, 4] : []))
                }
            }
            .scaleEffect(state.isLifted ? 1.02 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 1), value: state.isLifted)
    }
}

/// Figure d'illustration : rectangle, ellipse, trait, flèche ou image.
struct FigureNode: View {
    let figure: Figure
    var state = NodeState()

    private var ink: Color { figure.color.ink(default: Color.primary.opacity(0.55)) }

    var body: some View {
        let frame = figure.frame
        Group {
            switch figure.kind {
            case .rectangle:
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(figure.isFilled ? ink.opacity(0.14) : .clear)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(ink, lineWidth: 1.5))
            case .ellipse:
                Ellipse()
                    .fill(figure.isFilled ? ink.opacity(0.14) : .clear)
                    .overlay(Ellipse().strokeBorder(ink, lineWidth: 1.5))
            case .line, .arrow:
                Canvas { context, _ in
                    let origin = CGPoint(x: frame.minX, y: frame.minY)
                    let a = figure.start - origin, b = figure.end - origin
                    var path = Path()
                    path.move(to: a)
                    path.addLine(to: b)
                    context.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                    if figure.kind == .arrow {
                        let u = (b - a).normalized, p = CGPoint(x: -u.y, y: u.x)
                        var head = Path()
                        head.move(to: b)
                        head.addLine(to: b - u * 12 + p * 6)
                        head.addLine(to: b - u * 12 - p * 6)
                        head.closeSubpath()
                        context.fill(head, with: .color(ink))
                    }
                }
            case .image:
                if let data = figure.imageData, let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().interpolation(.high)
                } else {
                    RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06))
                        .overlay(Image(systemName: "photo.fill").foregroundStyle(.tertiary))
                }
            }
        }
        .frame(width: frame.width, height: frame.height)
        // Un trait ne se saisit que près de lui, pas dans tout son cadre.
        .contentShape(FigureHitShape(figure: figure))
        .overlay {
            if state.isSelected && !figure.kind.isStroke {
                Rectangle().strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
        }
        .opacity(state.isLifted ? 0.85 : 1)
    }
}

/// Zone cliquable d'une figure : le cadre, ou une bande de 14 points autour d'un trait.
private struct FigureHitShape: Shape {
    let figure: Figure

    func path(in rect: CGRect) -> Path {
        guard figure.kind.isStroke else { return Path(rect) }
        let origin = CGPoint(x: figure.frame.minX, y: figure.frame.minY)
        var line = Path()
        line.move(to: figure.start - origin)
        line.addLine(to: figure.end - origin)
        return line.strokedPath(StrokeStyle(lineWidth: 14, lineCap: .round))
    }
}
