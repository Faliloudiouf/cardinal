// Vues calculées par le moteur : MLD graphique, diagramme de classes UML, script SQL.
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import { doc, useDocument } from '../modele/document'
import { Moteur } from '../moteur/moteur'
import type { MLD, P, UML } from '../moteur/types'
import { tronquer } from './texte'
import { commandesCanevas } from './Canevas'

/** Surface qu'on fait glisser (souris ou molette) et qu'on zoome (Ctrl + molette, ruban). */
function Plan({ largeur, hauteur, children, etiquette }: { largeur: number; hauteur: number; children: ReactNode; etiquette: string }) {
  const { zoom } = useDocument()
  const zone = useRef<HTMLDivElement>(null)
  const [vue, setVue] = useState({ x: 0, y: 0 })
  const glisse = useRef<{ x: number; y: number; vx: number; vy: number } | null>(null)

  // Ajuster : tout le diagramme visible et centré, sans dépasser 100 %.
  const ajuster = useCallback(() => {
    const b = zone.current?.getBoundingClientRect()
    if (!b || largeur <= 0 || hauteur <= 0) return
    const z = Math.max(0.25, Math.min(1, (b.width - 32) / largeur, (b.height - 32) / hauteur))
    doc.regler({ zoom: z })
    setVue({ x: (b.width - largeur * z) / 2, y: (b.height - hauteur * z) / 2 })
  }, [largeur, hauteur])

  useEffect(() => {
    commandesCanevas.ajuster = ajuster
  }, [ajuster])

  // À l'ouverture de la vue : ajustée à la fenêtre.
  const ajustee = useRef(false)
  useLayoutEffect(() => {
    if (ajustee.current) return
    ajustee.current = true
    ajuster()
  }, [ajuster])

  useEffect(() => {
    const el = zone.current
    if (!el) return
    const bloquer = (e: WheelEvent) => e.preventDefault()
    el.addEventListener('wheel', bloquer, { passive: false })
    return () => el.removeEventListener('wheel', bloquer)
  }, [])

  return (
    <div
      ref={zone} className="plan" tabIndex={0} aria-label={etiquette}
      onWheel={(e) => {
        if (e.ctrlKey || e.metaKey) doc.regler({ zoom: Math.min(3, Math.max(0.25, zoom * Math.exp(-e.deltaY * 0.0022))) })
        else setVue((v) => ({ x: v.x - e.deltaX, y: v.y - e.deltaY }))
      }}
      onPointerDown={(e) => {
        glisse.current = { x: e.clientX, y: e.clientY, vx: vue.x, vy: vue.y }
        ;(e.target as Element).setPointerCapture(e.pointerId)
      }}
      onPointerMove={(e) => {
        const g = glisse.current
        if (g) setVue({ x: g.vx + e.clientX - g.x, y: g.vy + e.clientY - g.y })
      }}
      onPointerUp={() => { glisse.current = null }}
    >
      <svg width="100%" height="100%">
        <g transform={`translate(${vue.x},${vue.y}) scale(${zoom})`}>{children}</g>
      </svg>
    </div>
  )
}

const chemin = (points: P[]) => points.map((p, i) => `${i ? 'L' : 'M'}${p.x},${p.y}`).join('')

function fleche(fin: P, depuis: P, longueur = 10, demi = 5): string {
  const n = Math.hypot(fin.x - depuis.x, fin.y - depuis.y) || 1
  const ux = (fin.x - depuis.x) / n
  const uy = (fin.y - depuis.y) / n
  const bx = fin.x - ux * longueur
  const by = fin.y - uy * longueur
  return `M${fin.x},${fin.y}L${bx - uy * demi},${by + ux * demi}L${bx + uy * demi},${by - ux * demi}Z`
}

function Vide({ texte }: { texte: string }) {
  return <div className="vue-vide"><p>{texte}</p></div>
}

export function VueMLD() {
  const { modele } = useDocument()
  const mld: MLD = useMemo(() => Moteur.mld(modele!), [modele])
  if (mld.tables.length === 0) return <Vide texte="Le MLD apparaîtra dès que le MCD contiendra une entité." />
  return (
    <Plan largeur={mld.taille.x} hauteur={mld.taille.y} etiquette="Modèle logique de données">
      <g className="mld">
        {mld.liens.map((l, i) => (
          <g key={i}>
            <path d={chemin(l.points)} className="lien-mld" />
            {l.points.length >= 2 && <path d={fleche(l.points[l.points.length - 1], l.points[l.points.length - 2])} className="fleche-mld" />}
          </g>
        ))}
        {mld.tables.map((t) => {
          const x = t.centre.x - t.taille.x / 2
          const y = t.centre.y - t.taille.y / 2
          const id = `mld-${t.nom}`
          return (
            <g key={t.nom} className={t.association ? 'table depuis-association' : 'table'}>
              <clipPath id={id}><rect x={x} y={y} width={t.taille.x} height={t.taille.y} rx={8} /></clipPath>
              <rect x={x} y={y} width={t.taille.x} height={t.taille.y} rx={8} className="corps" />
              <rect x={x} y={y} width={t.taille.x} height={34} clipPath={`url(#${id})`} className="entete" />
              <text x={x + t.taille.x / 2} y={y + 21.5} className="titre-table">{tronquer(t.nom, t.taille.x - 20, 13, 600)}</text>
              {t.colonnes.map((c, i) => {
                const ly = y + 34 + 4 + i * 25 + 16.5
                const etranger = !!c.reference
                return (
                  <g key={c.nom}>
                    <text x={x + 12} y={ly} className={`colonne${c.cle ? ' primaire' : ''}${etranger ? ' etrangere' : ''}`}>
                      {etranger && <tspan className="diese">#</tspan>}{tronquer(c.nom, t.taille.x * 0.55, 12, c.cle ? 600 : 400)}
                    </text>
                    <text x={x + t.taille.x - 12} y={ly} className="type-colonne">
                      {tronquer(c.type + (c.nulle ? '' : ' *'), t.taille.x * 0.4, 10.5, 400, true)}
                    </text>
                  </g>
                )
              })}
              <rect x={x} y={y} width={t.taille.x} height={t.taille.y} rx={8} className="contour" />
            </g>
          )
        })}
      </g>
    </Plan>
  )
}

export function VueUML() {
  const { modele, umlSimplifie } = useDocument()
  const uml: UML = useMemo(() => Moteur.uml(modele!, umlSimplifie), [modele, umlSimplifie])
  if (uml.classes.length === 0) return <Vide texte="Le diagramme de classes apparaîtra dès que le MCD contiendra une entité." />
  const minX = Math.min(...uml.classes.map((c) => c.cadre.x), ...uml.etiquettes.map((e) => e.cadre.x)) - 40
  const minY = Math.min(...uml.classes.map((c) => c.cadre.y), ...uml.etiquettes.map((e) => e.cadre.y)) - 40
  return (
    <Plan largeur={uml.taille.x} hauteur={uml.taille.y} etiquette="Diagramme de classes UML">
      <g className="uml" transform={`translate(${-minX},${-minY})`}>
        {uml.traits.map((t, i) => (
          <g key={i}>
            <path d={chemin(t.points)} className={`trait-uml ${t.style}`} />
            {t.style === 'generalisation' && t.points.length >= 2 && (
              <path d={fleche(t.points[t.points.length - 1], t.points[t.points.length - 2], 15, 8)} className="pointe-generalisation" />
            )}
          </g>
        ))}
        {uml.losanges.map((l, i) => (
          <path key={i} className="losange" d={`M${l.centre.x},${l.centre.y - 15}L${l.centre.x + 15},${l.centre.y}L${l.centre.x},${l.centre.y + 15}L${l.centre.x - 15},${l.centre.y}Z`} />
        ))}
        {uml.classes.map((c) => {
          const { x, y, w, h } = c.cadre
          return (
            <g key={c.id} className={c.classeAssociation ? 'classe association' : 'classe'}>
              <rect x={x} y={y} width={w} height={h} className="corps" />
              <rect x={x} y={y} width={w} height={umlSimplifie ? h : 32} className="entete" />
              <text x={x + w / 2} y={y + (umlSimplifie ? h / 2 + 4.5 : 20.5)} className="nom-classe">{tronquer(c.nom, w - 16, 13, 600)}</text>
              {!umlSimplifie && (
                <>
                  <line x1={x} x2={x + w} y1={y + 32} y2={y + 32} className="separateur" />
                  {c.lignes.map((l, i) => (
                    <text key={i} x={x + 10} y={y + 32 + 8 + i * 20 + 14} className={`ligne-uml${l.identifiant ? ' identifiant' : ''}`}>
                      {l.texte}{l.identifiant ? ' {id}' : ''}
                    </text>
                  ))}
                  <line x1={x} x2={x + w} y1={y + h - 13} y2={y + h - 13} className="separateur" />
                </>
              )}
              <rect x={x} y={y} width={w} height={h} className="contour" />
            </g>
          )
        })}
        {uml.etiquettes.map((e, i) => (
          <text key={i} x={e.cadre.x + e.cadre.w / 2} y={e.cadre.y + e.cadre.h / 2 + 4} className={`etiquette-uml ${e.genre}`}>{e.texte}</text>
        ))}
      </g>
    </Plan>
  )
}

/** Coloration simple du SQL : mots-clés, chaînes, commentaires, nombres. */
function colorer(sql: string): ReactNode[] {
  const motif = /(--[^\n]*)|('(?:[^']|'')*')|\b(CREATE|TABLE|PRIMARY|FOREIGN|KEY|REFERENCES|NOT|NULL|UNIQUE|CONSTRAINT|CHECK|DEFAULT|ALTER|ADD|INDEX|ON|DELETE|UPDATE|CASCADE|COMMENT|IS|IN|AND|OR|ENUM|AUTO_INCREMENT|GENERATED|ALWAYS|BY|AS|IDENTITY|AUTOINCREMENT|DEFERRABLE|INITIALLY|DEFERRED|COLLATE|TYPE|IF|EXISTS|SET|COLUMN)\b|\b(\d+)\b/g
  const morceaux: ReactNode[] = []
  let dernier = 0
  let n = 0
  for (const m of sql.matchAll(motif)) {
    if (m.index > dernier) morceaux.push(sql.slice(dernier, m.index))
    const classe = m[1] ? 'sql-commentaire' : m[2] ? 'sql-chaine' : m[3] ? 'sql-mot' : 'sql-nombre'
    morceaux.push(<span key={n++} className={classe}>{m[0]}</span>)
    dernier = m.index + m[0].length
  }
  morceaux.push(sql.slice(dernier))
  return morceaux
}

export function VueSQL() {
  const { modele, sgbd } = useDocument()
  const script = useMemo(() => Moteur.sql(modele!, sgbd), [modele, sgbd])
  const lignes = script.split('\n').length
  return (
    <div className="vue-sql">
      <div className="sql-numeros" aria-hidden="true">{Array.from({ length: lignes }, (_, i) => <div key={i}>{i + 1}</div>)}</div>
      <pre className="sql-code" tabIndex={0} aria-label={`Script SQL pour ${sgbd}`}>{colorer(script)}</pre>
    </div>
  )
}
