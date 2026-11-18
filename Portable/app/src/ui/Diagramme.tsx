// Dessin complet d'un MCD en SVG : illustrations, liens, nœuds. Les tracés des pattes et la place
// des cardinalités viennent du moteur (mêmes règles de lisibilité que sur Mac).
import { memo, type ReactNode } from 'react'
import type { Association, Contrainte, Dessin, Entite, Figure, Heritage, Modele, Note, P, Regle, Attribut } from '../moteur/types'
import { cle } from '../modele/refs'
import { lignes, tronquer } from './texte'

export const M = {
  largeurEntite: 200, largeurAssociation: 176, entete: 34, rang: 21, marge: 8, associationNue: 44,
  heritage: { w: 58, h: 48 }, contrainte: 46, regle: { w: 220, h: 40 }, largeurNote: 240,
}

export interface Etats {
  selection: Set<string>
  souleves?: Set<string>
  attente?: string | null
}

const ETATS_VIDES: Etats = { selection: new Set() }

function centre(m: Modele, c: string): P {
  const [genre, id] = c.split(':')
  const liste = ({ entity: m.entities, association: m.associations, inheritance: m.inheritances, constraint: m.constraints,
    rule: m.rules, note: m.notes, figure: m.figures } as Record<string, { id: string; position: [number, number] }[]>)[genre]
  const p = liste?.find((e) => e.id === id)?.position ?? [0, 0]
  return { x: p[0], y: p[1] }
}

function bord(c: P, vers: P, w: number, h: number): P {
  const dx = vers.x - c.x
  const dy = vers.y - c.y
  if (dx === 0 && dy === 0) return c
  const t = Math.min(dx === 0 ? Infinity : w / 2 / Math.abs(dx), dy === 0 ? Infinity : h / 2 / Math.abs(dy), 1)
  return { x: c.x + dx * t, y: c.y + dy * t }
}

function pointe(pointe: P, depuis: P, taille = 10): string {
  const lx = pointe.x - depuis.x
  const ly = pointe.y - depuis.y
  const n = Math.hypot(lx, ly) || 1
  const ux = lx / n
  const uy = ly / n
  const bx = pointe.x - ux * taille
  const by = pointe.y - uy * taille
  return `M${pointe.x},${pointe.y}L${bx - uy * 5},${by + ux * 5}L${bx + uy * 5},${by - ux * 5}Z`
}

const chemin = (points: P[]) => points.map((p, i) => `${i ? 'L' : 'M'}${p.x},${p.y}`).join('')

export const Diagramme = memo(function Diagramme({ modele, dessin, etats = ETATS_VIDES, types }: {
  modele: Modele
  dessin: Dessin
  etats?: Etats
  types: Map<string, string>
}) {
  const s = modele.settings
  const tailleDe = new Map(dessin.noeuds.map((n) => [cle(n.ref), n.cadre]))
  const visibles = new Set(tailleDe.keys())
  const port = (source: string, cible: string) => dessin.ports[`${source}>${cible}`]
  const etat = (c: string) => ({ choisi: etats.selection.has(c), souleve: etats.souleves?.has(c) ?? false, attente: etats.attente === c })

  const liens: ReactNode[] = []
  for (const h of modele.inheritances) {
    const c = `inheritance:${h.id}`
    if (!visibles.has(c)) continue
    const p = centre(modele, c)
    const haut = { x: p.x, y: p.y - M.heritage.h / 2 }
    const bas = { x: p.x, y: p.y + M.heritage.h / 2 }
    if (h.parentID && visibles.has(`entity:${h.parentID}`)) {
      const fin = port(c, `entity:${h.parentID}`)
      if (fin) liens.push(<line key={`${c}-p`} x1={haut.x} y1={haut.y} x2={fin.x} y2={fin.y} className="lien-heritage parent" />)
    }
    for (const enfant of h.childIDs) {
      const fin = port(c, `entity:${enfant}`)
      if (fin && visibles.has(`entity:${enfant}`)) liens.push(<line key={`${c}-${enfant}`} x1={bas.x} y1={bas.y} x2={fin.x} y2={fin.y} className="lien-heritage" />)
    }
  }
  for (const k of modele.constraints) {
    const c = `constraint:${k.id}`
    if (!visibles.has(c)) continue
    const p = centre(modele, c)
    for (const l of k.links) {
      const fin = port(c, cle(l.target))
      if (!fin) continue
      const debut = bord(p, fin, M.contrainte, M.contrainte)
      liens.push(<line key={`${c}-${l.id}`} x1={debut.x} y1={debut.y} x2={fin.x} y2={fin.y} className="lien-contrainte" />)
      if (l.isTarget) liens.push(<path key={`${c}-${l.id}-f`} d={pointe(fin, debut)} className="fleche-contrainte" />)
    }
  }
  for (const r of modele.rules) {
    const c = `rule:${r.id}`
    if (!visibles.has(c)) continue
    const p = centre(modele, c)
    r.links.forEach((cible, i) => {
      const fin = port(c, cle(cible))
      if (!fin) return
      const debut = bord(p, fin, M.regle.w, M.regle.h)
      liens.push(<line key={`${c}-${i}`} x1={debut.x} y1={debut.y} x2={fin.x} y2={fin.y} className="lien-regle" />)
    })
  }

  return (
    <g className="diagramme">
      {modele.figures.filter((f) => visibles.has(`figure:${f.id}`)).map((f) => (
        <NoeudFigure key={f.id} figure={f} {...etat(`figure:${f.id}`)} />
      ))}
      <g className="pattes">
        {dessin.pattes.map((p) => (
          <g key={`${p.association}-${p.patte}`}>
            <path d={chemin(p.points)} className="patte" />
            {s.showDependencies && p.maxUn && p.points.length >= 2 && <path d={pointe(p.points[0], p.points[1])} className="fleche-df" />}
          </g>
        ))}
      </g>
      {liens}
      <g className="cardinalites">
        {dessin.etiquettes.map((e) => (
          <g key={`${e.association}-${e.patte}`}>
            <rect x={e.cadre.x} y={e.cadre.y} width={e.cadre.w} height={e.cadre.h} rx={e.cadre.h / 2} className="pastille" />
            <text x={e.cadre.x + e.cadre.w / 2} y={e.cadre.y + e.cadre.h / 2 + 4} className="pastille-texte">{e.texte}</text>
          </g>
        ))}
      </g>
      {modele.notes.filter((n) => visibles.has(`note:${n.id}`)).map((n) => <NoeudNote key={n.id} note={n} {...etat(`note:${n.id}`)} />)}
      {modele.associations.filter((a) => visibles.has(`association:${a.id}`)).map((a) => (
        <NoeudAssociation key={a.id} association={a} montrerAttributs={s.showAttributes} montrerTypes={s.showTypes} types={types} {...etat(`association:${a.id}`)} />
      ))}
      {modele.inheritances.filter((h) => visibles.has(`inheritance:${h.id}`)).map((h) => <NoeudHeritage key={h.id} heritage={h} {...etat(`inheritance:${h.id}`)} />)}
      {modele.constraints.filter((k) => visibles.has(`constraint:${k.id}`)).map((k) => <NoeudContrainte key={k.id} contrainte={k} {...etat(`constraint:${k.id}`)} />)}
      {modele.rules.filter((r) => visibles.has(`rule:${r.id}`)).map((r) => <NoeudRegle key={r.id} regle={r} {...etat(`rule:${r.id}`)} />)}
      {modele.entities.filter((e) => visibles.has(`entity:${e.id}`)).map((e) => (
        <NoeudEntite key={e.id} entite={e} montrerAttributs={s.showAttributes} montrerTypes={s.showTypes} types={types} {...etat(`entity:${e.id}`)} />
      ))}
    </g>
  )
})

interface EtatNoeud { choisi: boolean; souleve: boolean; attente: boolean }

function classes(base: string, e: EtatNoeud, couleur?: string) {
  return [base, e.choisi && 'choisi', e.souleve && 'souleve', e.attente && 'attente', couleur && couleur !== 'auto' && `c-${couleur}`]
    .filter(Boolean).join(' ')
}

export function tailleEntite(e: Entite, attributs: boolean) {
  return attributs ? { w: M.largeurEntite, h: M.entete + Math.max(e.attributes.length, 1) * M.rang + M.marge * 2 } : { w: M.largeurEntite, h: M.entete + 6 }
}

export function tailleAssociation(a: Association, attributs: boolean) {
  return a.attributes.length === 0 || !attributs
    ? { w: M.largeurAssociation, h: M.associationNue }
    : { w: M.largeurAssociation, h: M.entete + a.attributes.length * M.rang + M.marge * 2 }
}

function Cle({ x, y }: { x: number; y: number }) {
  // Clé pleine (même famille que les icônes du ruban), 9 px.
  return (
    <path transform={`translate(${x},${y}) scale(0.0352)`} className="cle"
      d="M216.57,39.43A80,80,0,0,0,83.91,120.78L28.69,176A15.86,15.86,0,0,0,24,187.31V216a16,16,0,0,0,16,16H72a8,8,0,0,0,8-8V208H96a8,8,0,0,0,8-8V184h16a8,8,0,0,0,5.66-2.34l9.56-9.57A79.73,79.73,0,0,0,160,176h.1A80,80,0,0,0,216.57,39.43ZM180,92a16,16,0,1,1,16-16A16,16,0,0,1,180,92Z" />
  )
}

function LigneAttribut({ a, x, y, largeur, montrerType, types }: { a: Attribut; x: number; y: number; largeur: number; montrerType: boolean; types: Map<string, string> }) {
  const type = montrerType ? (types.get(a.id) ?? '') + (a.isNotNull ? ' *' : '') : ''
  const placeType = type ? Math.min(largeur * 0.55, type.length * 6.6 + 6) : 0
  const nom = a.name || 'sans nom'
  const graisse = a.isIdentifier ? 600 : 400
  const espaceNom = largeur - 16 - placeType - (a.isUnique ? 14 : 0)
  const affiche = tronquer(nom, espaceNom, 12, graisse)
  return (
    <g>
      {a.isIdentifier && <Cle x={x} y={y - 8.5} />}
      <text x={x + 16} y={y} className={`attribut${a.isIdentifier ? ' identifiant' : ''}${a.name ? '' : ' vide'}`}>{affiche}</text>
      {a.isUnique && <text x={x + 16 + Math.min(espaceNom, affiche.length * 7) + 5} y={y - 0.5} className="badge-u">U</text>}
      {type && <text x={x + largeur} y={y} className="type-attribut">{tronquer(type, placeType, 10.5, 400, true)}</text>}
    </g>
  )
}

function Chrome({ e, children }: { e: EtatNoeud; children: ReactNode }) {
  return <g className={e.souleve ? 'souleve-anim' : undefined}>{children}</g>
}

function NoeudEntite({ entite, montrerAttributs, montrerTypes, types, ...e }: { entite: Entite; montrerAttributs: boolean; montrerTypes: boolean; types: Map<string, string> } & EtatNoeud) {
  const t = tailleEntite(entite, montrerAttributs)
  const x = entite.position[0] - t.w / 2
  const y = entite.position[1] - t.h / 2
  const hEntete = montrerAttributs ? M.entete : t.h
  const id = `clip-${entite.id}`
  return (
    <Chrome e={e}>
      <g className={classes('noeud entite', e, entite.color)} data-cle={`entity:${entite.id}`}>
        <clipPath id={id}><rect x={x} y={y} width={t.w} height={t.h} rx={9} /></clipPath>
        <rect x={x} y={y} width={t.w} height={t.h} rx={9} className="corps" />
        <rect x={x} y={y} width={t.w} height={hEntete} clipPath={`url(#${id})`} className={entite.isFictive ? 'entete fictive' : 'entete'} />
        <text x={x + t.w / 2} y={y + hEntete / 2 + 4.5} className={entite.isFictive ? 'titre-entite fictive' : 'titre-entite'}>
          {tronquer(entite.name || 'Sans nom', t.w - (entite.isFictive ? 70 : 20), 13, 600)}
          {entite.isFictive && <tspan className="mention-fictive" dx="5">FICTIVE</tspan>}
        </text>
        {montrerAttributs && entite.attributes.length === 0 && (
          <text x={x + 10} y={y + M.entete + M.marge + 14.5} className="aucune">Aucune propriété</text>
        )}
        {montrerAttributs && entite.attributes.map((a, i) => (
          <LigneAttribut key={a.id} a={a} x={x + 10} y={y + M.entete + M.marge + i * M.rang + 14.5} largeur={t.w - 20} montrerType={montrerTypes} types={types} />
        ))}
        <rect x={x} y={y} width={t.w} height={t.h} rx={9} className={entite.isFictive ? 'contour pointille' : 'contour'} />
        {e.attente && <rect x={x - 5} y={y - 5} width={t.w + 10} height={t.h + 10} rx={13} className="halo-attente" />}
      </g>
    </Chrome>
  )
}

function NoeudAssociation({ association, montrerAttributs, montrerTypes, types, ...e }: { association: Association; montrerAttributs: boolean; montrerTypes: boolean; types: Map<string, string> } & EtatNoeud) {
  const t = tailleAssociation(association, montrerAttributs)
  const nue = association.attributes.length === 0 || !montrerAttributs
  const x = association.position[0] - t.w / 2
  const y = association.position[1] - t.h / 2
  const rayon = nue ? t.h / 2 : 20
  return (
    <Chrome e={e}>
      <g className={classes('noeud association', e, association.color)} data-cle={`association:${association.id}`}>
        <rect x={x} y={y} width={t.w} height={t.h} rx={rayon} className="corps" />
        <rect x={x} y={y} width={t.w} height={t.h} rx={rayon} className="voile" />
        <text x={x + t.w / 2} y={nue ? y + t.h / 2 + 4.5 : y + M.entete / 2 + 4.5} className="titre-association">
          {tronquer(association.name || 'Sans nom', t.w - 28, 12.5, 600)}
        </text>
        {!nue && <line x1={x + 14} x2={x + t.w - 14} y1={y + M.entete} y2={y + M.entete} className="separateur" />}
        {!nue && association.attributes.map((a, i) => (
          <LigneAttribut key={a.id} a={a} x={x + 14} y={y + M.entete + M.marge + i * M.rang + 14.5} largeur={t.w - 28} montrerType={montrerTypes} types={types} />
        ))}
        <rect x={x} y={y} width={t.w} height={t.h} rx={rayon} className="contour" />
        {e.attente && <rect x={x - 5} y={y - 5} width={t.w + 10} height={t.h + 10} rx={rayon + 5} className="halo-attente" />}
      </g>
    </Chrome>
  )
}

function NoeudHeritage({ heritage, ...e }: { heritage: Heritage } & EtatNoeud) {
  const [cx, cy] = heritage.position
  const { w, h } = M.heritage
  const d = `M${cx},${cy - h / 2}L${cx + w / 2},${cy + h / 2}L${cx - w / 2},${cy + h / 2}Z`
  return (
    <g className={classes('noeud heritage', e)} data-cle={`inheritance:${heritage.id}`}>
      <path d={d} className="corps" />
      <path d={d} className="contour" />
      <text x={cx} y={cy + h / 2 - 9} className="sigle-heritage">{heritage.kind}</text>
    </g>
  )
}

function NoeudContrainte({ contrainte, ...e }: { contrainte: Contrainte } & EtatNoeud) {
  const [cx, cy] = contrainte.position
  const cif = contrainte.kind === 'CIF'
  return (
    <g className={classes(cif ? 'noeud contrainte cif' : 'noeud contrainte', e)} data-cle={`constraint:${contrainte.id}`}>
      <circle cx={cx} cy={cy} r={M.contrainte / 2} className="corps" />
      <circle cx={cx} cy={cy} r={M.contrainte / 2} className="voile" />
      <circle cx={cx} cy={cy} r={M.contrainte / 2} className="contour" />
      <text x={cx} y={cy + (cif ? 4 : 4.5)} className="sigle-contrainte">{contrainte.kind}</text>
    </g>
  )
}

function NoeudRegle({ regle, ...e }: { regle: Regle } & EtatNoeud) {
  const { w, h } = M.regle
  const x = regle.position[0] - w / 2
  const y = regle.position[1] - h / 2
  return (
    <g className={classes('noeud regle', e)} data-cle={`rule:${regle.id}`}>
      <rect x={x} y={y} width={w} height={h} rx={7} className="corps" />
      <rect x={x} y={y} width={w} height={h} rx={7} className="voile" />
      <text x={x + w / 2} y={y + h / 2 + 4} className="titre-regle">{tronquer(regle.name || 'Règle', w - 24, 12, 500)}</text>
      <rect x={x} y={y} width={w} height={h} rx={7} className="contour pointille" />
    </g>
  )
}

export function tailleNote(n: Note) {
  if (n.style === 'titre') return { w: Math.min(560, Math.max(120, n.text.length * 12.5 + 28)), h: 40 }
  const nb = n.text.split('\n').map((l) => Math.max(1, Math.ceil(l.length / 34))).reduce((a, b) => a + b, 0)
  return { w: M.largeurNote, h: Math.max(nb, 1) * 17 + 20 }
}

function NoeudNote({ note, ...e }: { note: Note } & EtatNoeud) {
  const t = tailleNote(note)
  const x = note.position[0] - t.w / 2
  const y = note.position[1] - t.h / 2
  const titre = note.style === 'titre'
  const texte = titre ? [tronquer(note.text || 'Titre', t.w - 16, 20, 700)] : lignes(note.text || 'Texte', t.w - 20, 12.5).slice(0, Math.round((t.h - 20) / 17))
  return (
    <g className={classes(titre ? 'noeud note titre' : 'noeud note', e)} data-cle={`note:${note.id}`}>
      <rect x={x} y={y} width={t.w} height={t.h} rx={6} className="fond-note" />
      {texte.map((l, i) => (
        <text key={i} x={titre ? x + t.w / 2 : x + 10} y={titre ? y + t.h / 2 + 7 : y + 10 + 12.5 + i * 17} className={titre ? 'texte-titre' : 'texte-note'}>{l}</text>
      ))}
      {(e.choisi || e.attente) && <rect x={x} y={y} width={t.w} height={t.h} rx={6} className="contour-note" />}
    </g>
  )
}

function NoeudFigure({ figure, ...e }: { figure: Figure } & EtatNoeud) {
  const [cx, cy] = figure.position
  const [w, h] = figure.size
  const cls = classes(`noeud figure${figure.isFilled ? ' remplie' : ''}`, e, figure.color)
  const c = `figure:${figure.id}`
  if (figure.kind === 'line' || figure.kind === 'arrow') {
    const a = { x: cx - figure.span[0] / 2, y: cy - figure.span[1] / 2 }
    const b = { x: cx + figure.span[0] / 2, y: cy + figure.span[1] / 2 }
    return (
      <g className={cls} data-cle={c}>
        <line x1={a.x} y1={a.y} x2={b.x} y2={b.y} className="zone-trait" />
        <line x1={a.x} y1={a.y} x2={b.x} y2={b.y} className="trait" />
        {figure.kind === 'arrow' && <path d={pointe(b, a, 12)} className="pointe" />}
      </g>
    )
  }
  if (figure.kind === 'image') {
    return (
      <g className={cls} data-cle={c}>
        {figure.imageData
          ? <image href={`data:image/png;base64,${figure.imageData}`} x={cx - w / 2} y={cy - h / 2} width={w} height={h} preserveAspectRatio="xMidYMid meet" />
          : <rect x={cx - w / 2} y={cy - h / 2} width={w} height={h} rx={6} className="image-vide" />}
        {e.choisi && <rect x={cx - w / 2} y={cy - h / 2} width={w} height={h} className="cadre-choix" />}
      </g>
    )
  }
  return (
    <g className={cls} data-cle={c}>
      {figure.kind === 'ellipse'
        ? <ellipse cx={cx} cy={cy} rx={w / 2} ry={h / 2} className="forme" />
        : <rect x={cx - w / 2} y={cy - h / 2} width={w} height={h} rx={6} className="forme" />}
    </g>
  )
}
