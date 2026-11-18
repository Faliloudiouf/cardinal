// Canevas interactif du MCD : sélection, glisser, lasso, création, liens, cassures, zoom.
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react'
import { doc, useDocument, type Outil } from '../modele/document'
import { estPivot, pivot, relier } from '../modele/liens'
import { genreDe, idDe, nouvelAttribut, nouvelId, elements } from '../modele/refs'
import { Moteur } from '../moteur/moteur'
import type { Modele, P } from '../moteur/types'
import { Diagramme } from './Diagramme'

type Geste =
  | { genre: 'deplacer'; depart: P; base: Modele; refs: string[]; bouge: boolean }
  | { genre: 'lasso'; depart: P; courant: P; base: string[] }
  | { genre: 'defiler'; depart: { x: number; y: number }; vue0: { x: number; y: number } }
  | { genre: 'cassure'; association: string; patte: string; base: Modele }

export const ZOOM_MIN = 0.25
export const ZOOM_MAX = 3

/** Commandes appelées depuis le ruban (ajuster à la fenêtre). */
export const commandesCanevas = { ajuster: () => {} }

function deplacer(m: Modele, refs: Set<string>, dx: number, dy: number): Modele {
  const copie: Modele = { ...m }
  const bouger = <T extends { id: string; position: [number, number] }>(liste: T[], genre: string) =>
    liste.map((e) => (refs.has(`${genre}:${e.id}`) ? { ...e, position: [e.position[0] + dx, e.position[1] + dy] as [number, number] } : e))
  copie.entities = bouger(m.entities, 'entity')
  copie.associations = bouger(m.associations, 'association').map((a) =>
    refs.has(`association:${a.id}`) && a.legs.some((l) => l.bend)
      ? { ...a, legs: a.legs.map((l) => (l.bend ? { ...l, bend: [l.bend[0] + dx, l.bend[1] + dy] as [number, number] } : l)) }
      : a,
  )
  copie.inheritances = bouger(m.inheritances, 'inheritance')
  copie.constraints = bouger(m.constraints, 'constraint')
  copie.rules = bouger(m.rules, 'rule')
  copie.notes = bouger(m.notes, 'note')
  copie.figures = bouger(m.figures, 'figure')
  return copie
}

const OUTILS_FIGURE: Partial<Record<Outil, 'rectangle' | 'ellipse' | 'line' | 'arrow'>> = {
  rectangle: 'rectangle', ellipse: 'ellipse', trait: 'line', fleche: 'arrow',
}

export function Canevas() {
  const etat = useDocument()
  const modele = etat.modele!
  const zone = useRef<HTMLDivElement>(null)
  const [vue, setVue] = useState({ x: 0, y: 0 })
  const [geste, setGeste] = useState<Geste | null>(null)
  const z = etat.zoom
  // Zoom précédent (pour garder le centre fixe) et point d'ancrage du zoom à la molette.
  const zPrecedent = useRef(z)
  const ancreZoom = useRef<P | null>(null)

  const visible = useMemo(() => {
    if (!etat.vue) return modele
    return modele // le moteur filtre la vue dans le dessin
  }, [modele, etat.vue])
  const dessin = useMemo(() => Moteur.dessin(visible, etat.vue), [visible, etat.vue])
  const types = useMemo(() => new Map(dessin.types.map((t) => [t.id, t.type])), [dessin])
  const selection = useMemo(() => new Set(etat.selection), [etat.selection])
  const souleves = useMemo(() => (geste?.genre === 'deplacer' && geste.bouge ? new Set(geste.refs) : undefined), [geste])

  // Ajuster : tout le diagramme visible, centré, sans dépasser 100 %.
  const ajuster = useCallback(() => {
    const boite = zone.current?.getBoundingClientRect()
    const l = Moteur.dessin(modele, etat.vue).limites
    if (!boite) return
    if (!l) {
      setVue({ x: 0, y: 0 })
      zPrecedent.current = 1
      doc.regler({ zoom: 1 })
      return
    }
    const nz = Math.max(ZOOM_MIN, Math.min(1, boite.width / l.w, boite.height / l.h))
    zPrecedent.current = nz // la position est calculée ici : l'effet du zoom ne doit pas la décaler
    doc.regler({ zoom: nz })
    setVue({ x: (boite.width - l.w * nz) / 2 - l.x * nz, y: (boite.height - l.h * nz) / 2 - l.y * nz })
  }, [modele, etat.vue])

  useEffect(() => {
    commandesCanevas.ajuster = ajuster
  }, [ajuster])

  // À l'ouverture d'un modèle ou d'une vue : ajusté à la fenêtre. Au montage, la mesure de la zone
  // force la mise en page : pas besoin d'attendre une image (suspendue si la fenêtre est cachée).
  const dernierAjuster = useRef(ajuster)
  dernierAjuster.current = ajuster
  useLayoutEffect(() => {
    dernierAjuster.current()
  }, [])

  // Zoom en gardant le centre de la fenêtre fixe quand il vient du ruban.
  useEffect(() => {
    if (zPrecedent.current === z) return
    const boite = zone.current?.getBoundingClientRect()
    const avant = zPrecedent.current
    zPrecedent.current = z
    if (!boite || ancreZoom.current) {
      ancreZoom.current = null
      return
    }
    const cx = boite.width / 2
    const cy = boite.height / 2
    setVue((v) => ({ x: cx - ((cx - v.x) / avant) * z, y: cy - ((cy - v.y) / avant) * z }))
  }, [z])

  function versModele(e: { clientX: number; clientY: number }): P {
    const b = zone.current!.getBoundingClientRect()
    return { x: (e.clientX - b.left - vue.x) / z, y: (e.clientY - b.top - vue.y) / z }
  }

  function surMolette(e: React.WheelEvent) {
    if (e.ctrlKey || e.metaKey) {
      const b = zone.current!.getBoundingClientRect()
      const px = e.clientX - b.left
      const py = e.clientY - b.top
      const nz = Math.min(ZOOM_MAX, Math.max(ZOOM_MIN, z * Math.exp(-e.deltaY * 0.0022)))
      ancreZoom.current = { x: px, y: py }
      zPrecedent.current = nz
      setVue((v) => ({ x: px - ((px - v.x) / z) * nz, y: py - ((py - v.y) / z) * nz }))
      doc.regler({ zoom: nz })
    } else {
      setVue((v) => ({ x: v.x - (e.shiftKey ? e.deltaY : e.deltaX), y: v.y - (e.shiftKey ? 0 : e.deltaY) }))
    }
  }

  // Wheel natif non passif : empêche le zoom de la page entière avec Ctrl + molette.
  useEffect(() => {
    const el = zone.current
    if (!el) return
    const bloquer = (e: WheelEvent) => e.preventDefault()
    el.addEventListener('wheel', bloquer, { passive: false })
    return () => el.removeEventListener('wheel', bloquer)
  }, [])

  function creer(outil: Outil, p: P) {
    const position: [number, number] = [Math.round(p.x), Math.round(p.y)]
    let cree = ''
    let enchainer = false
    doc.modifier((m) => {
      const id = nouvelId()
      switch (outil) {
        case 'entite':
          m.entities.push({ id, name: Moteur.nomLibre(m, 'Entité'), attributes: [{ ...nouvelAttribut('id', true), type: 'int' }], position, isFictive: false, color: 'auto' })
          cree = `entity:${id}`
          break
        case 'association':
          m.associations.push({ id, name: Moteur.nomLibre(m, 'Association'), attributes: [], legs: [], position, color: 'auto' })
          cree = `association:${id}`
          break
        case 'heritage':
          m.inheritances.push({ id, childIDs: [], kind: '', strategy: 'tablesSousTypes', position })
          cree = `inheritance:${id}`
          enchainer = true
          break
        case 'contrainte':
        case 'cif':
          m.constraints.push({ id, kind: outil === 'cif' ? 'CIF' : 'X', links: [], position, sql: '' })
          cree = `constraint:${id}`
          enchainer = true
          break
        case 'regle':
          m.rules.push({ id, name: Moteur.nomLibre(m, 'Règle'), details: '', sql: '', links: [], position })
          cree = `rule:${id}`
          enchainer = true
          break
        case 'note':
          m.notes.push({ id, text: 'Texte', style: 'texte', position })
          cree = `note:${id}`
          break
        default: {
          const forme = OUTILS_FIGURE[outil]
          if (!forme) return
          m.figures.push({ id, kind: forme, position, size: forme === 'ellipse' ? [140, 100] : [160, 100], span: [160, 0], color: 'auto', isFilled: false })
          cree = `figure:${id}`
        }
      }
      // Un élément créé dans une vue en fait partie.
      const v = m.views.find((x) => x.id === doc.etat.vue)
      if (v && cree) v.refs.push({ [genreDe(cree)]: { _0: idDe(cree) } })
    })
    if (!cree) return
    doc.selectionner([cree])
    doc.regler(enchainer ? { outil: 'lien', attente: cree } : { outil: 'selection', attente: null })
  }

  function clicLien(c: string) {
    if (genreDe(c) === 'figure') return
    const premier = doc.etat.attente
    if (!premier || premier === c) {
      doc.regler({ attente: c })
      return
    }
    const m = structuredClone(modele)
    if (relier(premier, c, m)) {
      // On garde le pivot (association, héritage, contrainte, règle) pour enchaîner les liens :
      // entité, association, entité suffit pour une association binaire.
      const centre = pivot(premier, c)
      doc.remplacer(m, [centre])
      doc.regler({ attente: estPivot(centre) ? centre : null })
    } else {
      doc.regler({ attente: c })
    }
  }

  function surAppui(e: React.PointerEvent) {
    if (e.button === 1 || (e.button === 0 && e.altKey)) {
      setGeste({ genre: 'defiler', depart: { x: e.clientX, y: e.clientY }, vue0: vue })
      ;(e.target as Element).setPointerCapture(e.pointerId)
      return
    }
    if (e.button !== 0) return
    zone.current?.focus()
    const cible = (e.target as Element).closest('[data-cle], [data-poignee]')
    const p = versModele(e)
    if (cible?.hasAttribute('data-poignee')) {
      const [association, patte] = cible.getAttribute('data-poignee')!.split('|')
      doc.debutGeste()
      setGeste({ genre: 'cassure', association, patte, base: modele })
      ;(e.target as Element).setPointerCapture(e.pointerId)
      return
    }
    const c = cible?.getAttribute('data-cle') ?? null
    if (!c) {
      if (etat.outil !== 'selection' && etat.outil !== 'lien') {
        creer(etat.outil, p)
        return
      }
      if (etat.outil === 'lien') doc.regler({ attente: null })
      const base = e.shiftKey || e.ctrlKey || e.metaKey ? etat.selection : []
      if (!e.shiftKey && !e.ctrlKey && !e.metaKey) doc.selectionner([])
      setGeste({ genre: 'lasso', depart: p, courant: p, base })
      ;(e.target as Element).setPointerCapture(e.pointerId)
      return
    }
    if (etat.outil === 'lien') {
      clicLien(c)
      return
    }
    let choix = etat.selection
    if (e.shiftKey || e.ctrlKey || e.metaKey) {
      choix = selection.has(c) ? choix.filter((x) => x !== c) : [...choix, c]
      doc.selectionner(choix)
      if (!choix.includes(c)) return
    } else if (!selection.has(c)) {
      choix = [c]
      doc.selectionner(choix)
    }
    doc.debutGeste()
    setGeste({ genre: 'deplacer', depart: p, base: modele, refs: choix, bouge: false })
    ;(e.target as Element).setPointerCapture(e.pointerId)
  }

  function surMouvement(e: React.PointerEvent) {
    if (!geste) return
    if (geste.genre === 'defiler') {
      setVue({ x: geste.vue0.x + e.clientX - geste.depart.x, y: geste.vue0.y + e.clientY - geste.depart.y })
      return
    }
    const p = versModele(e)
    if (geste.genre === 'deplacer') {
      const dx = Math.round(p.x - geste.depart.x)
      const dy = Math.round(p.y - geste.depart.y)
      if (!geste.bouge && Math.hypot(dx, dy) * z < 3) return
      if (!geste.bouge) setGeste({ ...geste, bouge: true })
      doc.pendantGeste(deplacer(geste.base, new Set(geste.refs), dx, dy))
    } else if (geste.genre === 'lasso') {
      setGeste({ ...geste, courant: p })
      const x1 = Math.min(geste.depart.x, p.x)
      const x2 = Math.max(geste.depart.x, p.x)
      const y1 = Math.min(geste.depart.y, p.y)
      const y2 = Math.max(geste.depart.y, p.y)
      const dedans = dessin.noeuds
        .filter(({ cadre: r }) => r.x < x2 && r.x + r.w > x1 && r.y < y2 && r.y + r.h > y1)
        .map((n) => `${Object.keys(n.ref)[0]}:${Object.values(n.ref)[0]!._0}`)
      doc.selectionner([...new Set([...geste.base, ...dedans])])
    } else if (geste.genre === 'cassure') {
      const m = structuredClone(geste.base)
      const patte = m.associations.find((a) => a.id === geste.association)?.legs.find((l) => l.id === geste.patte)
      if (patte) patte.bend = [Math.round(p.x), Math.round(p.y)]
      doc.pendantGeste(m)
    }
  }

  function surRelache() {
    if (geste?.genre === 'deplacer' || geste?.genre === 'cassure') doc.finGeste()
    setGeste(null)
  }

  // Double-clic : sur une patte, ajoute ou retire une cassure ; sur un nœud, place le curseur dans l'inspecteur.
  function surDoubleClic(e: React.MouseEvent) {
    const cible = (e.target as Element).closest('[data-cle]')
    if (cible) {
      window.dispatchEvent(new CustomEvent('cardinal:renommer'))
      return
    }
    if (etat.outil === 'selection') creer('entite', versModele(e))
  }

  const lasso = geste?.genre === 'lasso' ? geste : null
  const quadrillage = modele.settings.showGrid
  const pas = 20 * z
  const poignees = modele.associations
    .filter((a) => selection.has(`association:${a.id}`))
    .flatMap((a) => a.legs.filter((l) => l.bend).map((l) => ({ a: a.id, l: l.id, p: l.bend! })))

  return (
    <div
      ref={zone}
      className={`canevas outil-${etat.outil}${geste?.genre === 'defiler' ? ' defile' : ''}`}
      tabIndex={0}
      aria-label="Diagramme entité-association"
      onWheel={surMolette}
      onPointerDown={surAppui}
      onPointerMove={surMouvement}
      onPointerUp={surRelache}
      onPointerCancel={surRelache}
      onDoubleClick={surDoubleClic}
      style={quadrillage ? {
        backgroundImage: `radial-gradient(circle, var(--grille) ${Math.max(0.8, 1.1 * Math.min(z, 1.4))}px, transparent 0)`,
        backgroundSize: `${pas}px ${pas}px`,
        backgroundPosition: `${vue.x % pas}px ${vue.y % pas}px`,
      } : undefined}
    >
      <svg className="toile" width="100%" height="100%">
        <g transform={`translate(${vue.x},${vue.y}) scale(${z})`}>
          <Diagramme modele={visible} dessin={dessin} types={types} etats={{ selection, souleves, attente: etat.attente }} />
          {poignees.map((h) => (
            <g key={h.l} data-poignee={`${h.a}|${h.l}`}>
              <circle cx={h.p[0]} cy={h.p[1]} r={12} className="poignee-zone" />
              <circle cx={h.p[0]} cy={h.p[1]} r={6} className="poignee" />
            </g>
          ))}
          {lasso && (
            <rect
              x={Math.min(lasso.depart.x, lasso.courant.x)} y={Math.min(lasso.depart.y, lasso.courant.y)}
              width={Math.abs(lasso.courant.x - lasso.depart.x)} height={Math.abs(lasso.courant.y - lasso.depart.y)}
              className="lasso" style={{ strokeWidth: 1 / z }}
            />
          )}
        </g>
      </svg>
      {elements(modele).length === 0 && (
        <div className="vide-canevas">
          <p className="vide-titre">Modèle vide</p>
          <p>Choisissez <strong>Entité</strong> dans le ruban puis cliquez ici, ou double-cliquez sur le canevas.</p>
        </div>
      )}
      {etat.outil === 'lien' && (
        <div className="consigne">
          {etat.attente ? 'Cliquez sur l’élément à relier. Échap pour terminer.' : 'Cliquez sur une entité, puis sur une association, un héritage ou une contrainte.'}
        </div>
      )}
    </div>
  )
}
