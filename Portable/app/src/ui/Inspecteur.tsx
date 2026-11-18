// Inspecteur : propriétés de l'élément sélectionné, modifiables directement.
import { useEffect, useMemo, useRef, useState } from 'react'
import { ArrowDown, ArrowUp, Key, Plus, Trash, WarningCircle, XCircle, CheckCircle, PencilSimple } from '@phosphor-icons/react'
import { doc, useDocument } from '../modele/document'
import { cle, genreDe, idDe, nomDe, nouvelAttribut, depuisCle } from '../modele/refs'
import { Moteur } from '../moteur/moteur'
import type { Attribut, Cardinalite, Couleur, Modele } from '../moteur/types'
import { EditeurAttribut } from './EditeurAttribut'
import * as A from '../modele/actions'

const COULEURS: { id: Couleur; libelle: string; teinte: string }[] = [
  { id: 'auto', libelle: 'Automatique', teinte: 'var(--entite-fond)' },
  { id: 'bleu', libelle: 'Bleu', teinte: '#2961b3' },
  { id: 'sarcelle', libelle: 'Sarcelle', teinte: '#0d7378' },
  { id: 'vert', libelle: 'Vert', teinte: '#2b7838' },
  { id: 'violet', libelle: 'Violet', teinte: '#6b42a3' },
  { id: 'rouge', libelle: 'Rouge', teinte: '#a83333' },
  { id: 'ardoise', libelle: 'Ardoise', teinte: '#4a5466' },
]

function modifier(recette: (m: Modele) => void) {
  doc.modifier(recette)
}

/** Champ texte qui n'enregistre qu'à la fin de la saisie (un seul pas d'annulation). */
function ChampTexte({ valeur, onValider, placeholder, etiquette, multiligne, mono, autoFocusEvent }: {
  valeur: string; onValider: (v: string) => void; placeholder?: string; etiquette: string; multiligne?: boolean; mono?: boolean; autoFocusEvent?: boolean
}) {
  const [texte, setTexte] = useState(valeur)
  const ref = useRef<HTMLInputElement & HTMLTextAreaElement>(null)
  useEffect(() => setTexte(valeur), [valeur])
  useEffect(() => {
    if (!autoFocusEvent) return
    const f = () => { ref.current?.focus(); ref.current?.select() }
    window.addEventListener('cardinal:renommer', f)
    return () => window.removeEventListener('cardinal:renommer', f)
  }, [autoFocusEvent])
  const valider = () => { if (texte !== valeur) onValider(texte) }
  const props = {
    ref, value: texte, placeholder, 'aria-label': etiquette, className: `champ${mono ? ' mono' : ''}`,
    onChange: (e: React.ChangeEvent<HTMLInputElement & HTMLTextAreaElement>) => setTexte(e.target.value),
    onBlur: valider,
  }
  return multiligne
    ? <textarea {...props} rows={mono ? 4 : 3} />
    : <input {...props} onKeyDown={(e) => { if (e.key === 'Enter') { valider(); (e.target as HTMLInputElement).blur() } if (e.key === 'Escape') setTexte(valeur) }} />
}

function Section({ titre, children, action }: { titre: string; children: React.ReactNode; action?: React.ReactNode }) {
  return (
    <section className="insp-section">
      <header><h4>{titre}</h4>{action}</header>
      {children}
    </section>
  )
}

function Couleurs({ valeur, onChange }: { valeur: Couleur; onChange: (c: Couleur) => void }) {
  return (
    <div className="couleurs" role="radiogroup" aria-label="Couleur">
      {COULEURS.map((c) => (
        <button key={c.id} role="radio" aria-checked={valeur === c.id} title={c.libelle} className="pastille-couleur"
          style={{ background: c.id === 'auto' ? 'conic-gradient(var(--entite-fond) 0 50%, var(--association) 0)' : c.teinte }}
          onClick={() => onChange(c.id)} />
      ))}
    </div>
  )
}

/** Liste des propriétés d'une entité ou d'une association. */
function ListeAttributs({ attributs, identifiants, maj }: { attributs: Attribut[]; identifiants: boolean; maj: (f: (liste: Attribut[]) => Attribut[]) => void }) {
  const [edite, setEdite] = useState<Attribut | null>(null)
  const types = useMemo(() => new Map(attributs.map((a) => [a.id, Moteur.attribut(a).affichage])), [attributs])
  return (
    <>
      <ul className="attributs">
        {attributs.length === 0 && <li className="vide">Aucune propriété</li>}
        {attributs.map((a, i) => (
          <li key={a.id} className="attribut-ligne">
            {identifiants && (
              <button className={`bascule-cle${a.isIdentifier ? ' actif' : ''}`} title={a.isIdentifier ? 'Identifiant (cliquer pour retirer)' : 'Faire de cette propriété un identifiant'}
                aria-pressed={a.isIdentifier}
                onClick={() => maj((l) => l.map((x) => (x.id === a.id ? { ...x, isIdentifier: !x.isIdentifier, isNotNull: false, isUnique: false } : x)))}>
                <Key size={13} weight="fill" />
              </button>
            )}
            <button className="attribut-nom" onDoubleClick={() => setEdite(a)} onClick={() => setEdite(a)} title="Modifier la propriété">
              <span className={a.isIdentifier ? 'souligne' : ''}>{a.name || 'sans nom'}</span>
              <code>{types.get(a.id)}</code>
            </button>
            <span className="attribut-outils">
              <button className="icone-seule" title="Monter" disabled={i === 0} onClick={() => maj((l) => { const c = [...l]; [c[i - 1], c[i]] = [c[i], c[i - 1]]; return c })}><ArrowUp size={13} weight="bold" /></button>
              <button className="icone-seule" title="Descendre" disabled={i === attributs.length - 1} onClick={() => maj((l) => { const c = [...l]; [c[i + 1], c[i]] = [c[i], c[i + 1]]; return c })}><ArrowDown size={13} weight="bold" /></button>
              <button className="icone-seule" title="Supprimer la propriété" onClick={() => maj((l) => l.filter((x) => x.id !== a.id))}><Trash size={13} weight="fill" /></button>
            </span>
          </li>
        ))}
      </ul>
      <button className="lien-action" onClick={() => {
        const nouveau = nouvelAttribut('')
        setEdite(nouveau)
      }}>
        <Plus size={14} weight="bold" /> Ajouter une propriété
      </button>
      {edite && (
        <EditeurAttribut
          attribut={edite} identifiantPossible={identifiants}
          onFermer={() => setEdite(null)}
          onValider={(a) => {
            maj((l) => (l.some((x) => x.id === a.id) ? l.map((x) => (x.id === a.id ? a : x)) : [...l, a]))
            setEdite(null)
          }}
        />
      )}
    </>
  )
}

function InspEntite({ m, id }: { m: Modele; id: string }) {
  const e = m.entities.find((x) => x.id === id)!
  const maj = (f: (x: typeof e) => void) => modifier((mm) => f(mm.entities.find((x) => x.id === id)!))
  const pattes = m.associations.flatMap((a) => a.legs.filter((l) => l.entityID === id).map((l) => ({ a, l })))
  return (
    <>
      <Section titre="Entité">
        <ChampTexte etiquette="Nom de l’entité" valeur={e.name} onValider={(v) => maj((x) => { x.name = v.trim() })} autoFocusEvent />
        <label className="case"><input type="checkbox" checked={e.isFictive} onChange={(ev) => maj((x) => { x.isFictive = ev.target.checked })} />Entité fictive (pas de table dans le MLD)</label>
        <Couleurs valeur={e.color} onChange={(c) => maj((x) => { x.color = c })} />
      </Section>
      <Section titre="Propriétés">
        <ListeAttributs attributs={e.attributes} identifiants maj={(f) => maj((x) => { x.attributes = f(x.attributes) })} />
      </Section>
      {pattes.length > 0 && (
        <Section titre="Associations">
          <ul className="liste-simple">
            {pattes.map(({ a, l }) => (
              <li key={l.id}><button className="lien-texte" onClick={() => doc.selectionner([`association:${a.id}`])}>{a.name || 'Sans nom'}</button><span className="pastille-card">{l.cardinality}</span></li>
            ))}
          </ul>
        </Section>
      )}
    </>
  )
}

const CARDINALITES: Cardinalite[] = ['0,1', '1,1', '0,N', '1,N']

function InspAssociation({ m, id }: { m: Modele; id: string }) {
  const a = m.associations.find((x) => x.id === id)!
  const maj = (f: (x: typeof a) => void) => modifier((mm) => f(mm.associations.find((x) => x.id === id)!))
  return (
    <>
      <Section titre="Association">
        <ChampTexte etiquette="Nom de l’association" valeur={a.name} onValider={(v) => maj((x) => { x.name = v.trim() })} autoFocusEvent />
        <Couleurs valeur={a.color} onChange={(c) => maj((x) => { x.color = c })} />
      </Section>
      <Section titre="Pattes">
        {a.legs.length === 0 && <p className="aide">Choisissez l’outil <strong>Lien</strong>, puis cliquez sur une entité et sur cette association.</p>}
        <ul className="pattes-liste">
          {a.legs.map((l) => (
            <li key={l.id}>
              <div className="patte-tete">
                <strong>{m.entities.find((e) => e.id === l.entityID)?.name || 'Entité'}</strong>
                <button className="icone-seule" title="Supprimer cette patte" onClick={() => maj((x) => { x.legs = x.legs.filter((y) => y.id !== l.id) })}><Trash size={13} weight="fill" /></button>
              </div>
              <div className="segmente" role="group" aria-label="Cardinalité">
                {CARDINALITES.map((c) => (
                  <button key={c} aria-pressed={l.cardinality === c} onClick={() => maj((x) => { x.legs.find((y) => y.id === l.id)!.cardinality = c })}>{c}</button>
                ))}
              </div>
              <div className="patte-options">
                <label className="case" title="Identifiant relatif : l’entité est identifiée en partie par l’autre entité">
                  <input type="checkbox" checked={l.isRelative} onChange={(ev) => maj((x) => { x.legs.find((y) => y.id === l.id)!.isRelative = ev.target.checked })} />(R)
                </label>
                <label className="case">
                  <input type="checkbox" checked={!!l.bend} onChange={() => doc.remplacer(Moteur.modifier(doc.etat.modele!, 'cassure', { association: id, patte: l.id }).modele)} />Cassure
                </label>
              </div>
              <ChampTexte etiquette="Rôle" placeholder="Rôle (facultatif)" valeur={l.role} onValider={(v) => maj((x) => { x.legs.find((y) => y.id === l.id)!.role = v.trim() })} />
            </li>
          ))}
        </ul>
      </Section>
      <Section titre="Propriétés">
        <ListeAttributs attributs={a.attributes} identifiants={false} maj={(f) => maj((x) => { x.attributes = f(x.attributes) })} />
      </Section>
    </>
  )
}

function InspHeritage({ m, id }: { m: Modele; id: string }) {
  const h = m.inheritances.find((x) => x.id === id)!
  const maj = (f: (x: typeof h) => void) => modifier((mm) => f(mm.inheritances.find((x) => x.id === id)!))
  const nom = (e: string) => m.entities.find((x) => x.id === e)?.name || 'Entité'
  return (
    <Section titre="Héritage">
      <label className="ligne-champ verticale">
        <span>Surtype</span>
        <select className="champ" value={h.parentID ?? ''} onChange={(e) => maj((x) => { x.parentID = e.target.value || null; x.childIDs = x.childIDs.filter((c) => c !== e.target.value) })}>
          <option value="">Aucun</option>
          {m.entities.map((e) => <option key={e.id} value={e.id}>{e.name || 'Sans nom'}</option>)}
        </select>
      </label>
      <div className="sous-titre">Sous-types</div>
      <ul className="liste-simple">
        {h.childIDs.length === 0 && <li className="vide">Reliez les sous-types avec l’outil Lien.</li>}
        {h.childIDs.map((c) => (
          <li key={c}>{nom(c)}<button className="icone-seule" title="Retirer ce sous-type" onClick={() => maj((x) => { x.childIDs = x.childIDs.filter((y) => y !== c) })}><Trash size={13} weight="fill" /></button></li>
        ))}
      </ul>
      <label className="ligne-champ verticale">
        <span>Contrainte</span>
        <select className="champ" value={h.kind} onChange={(e) => maj((x) => { x.kind = e.target.value as typeof h.kind })}>
          <option value="">Sans contrainte</option><option value="X">Exclusion (X)</option><option value="T">Totalité (T)</option><option value="XT">Partition (XT)</option>
        </select>
      </label>
      <label className="ligne-champ verticale">
        <span>Traduction dans le MLD</span>
        <select className="champ" value={h.strategy} onChange={(e) => maj((x) => { x.strategy = e.target.value as typeof h.strategy })}>
          <option value="tablesSousTypes">Une table par type</option><option value="sousTypesSeuls">Sous-types seuls (propriétés migrées)</option><option value="surtypeSeul">Surtype seul (avec discriminant)</option>
        </select>
      </label>
    </Section>
  )
}

const GENRES_CONTRAINTE = [
  ['CIF', 'Contrainte d’intégrité fonctionnelle (CIF)'], ['I', 'Inclusion (I)'], ['X', 'Exclusion (X)'], ['T', 'Totalité (T)'],
  ['XT', 'Partition (XT)'], ['S', 'Simultanéité (S)'], ['=', 'Égalité (=)'],
] as const

function InspContrainte({ m, id }: { m: Modele; id: string }) {
  const k = m.constraints.find((x) => x.id === id)!
  const maj = (f: (x: typeof k) => void) => modifier((mm) => f(mm.constraints.find((x) => x.id === id)!))
  return (
    <Section titre="Contrainte">
      <select className="champ" aria-label="Genre de contrainte" value={k.kind} onChange={(e) => maj((x) => { x.kind = e.target.value as typeof k.kind })}>
        {GENRES_CONTRAINTE.map(([v, l]) => <option key={v} value={v}>{l}</option>)}
      </select>
      <div className="sous-titre">Éléments reliés</div>
      <ul className="liste-simple">
        {k.links.length === 0 && <li className="vide">Reliez-la avec l’outil Lien.</li>}
        {k.links.map((l) => (
          <li key={l.id}>
            <span>{nomDe(m, cle(l.target))}</span>
            {k.kind === 'CIF' && genreDe(cle(l.target)) === 'entity' && (
              <label className="case" title="Entité déterminée (pointe de la flèche)"><input type="checkbox" checked={l.isTarget} onChange={(e) => maj((x) => { x.links.find((y) => y.id === l.id)!.isTarget = e.target.checked })} />Cible</label>
            )}
            <button className="icone-seule" title="Retirer ce lien" onClick={() => maj((x) => { x.links = x.links.filter((y) => y.id !== l.id) })}><Trash size={13} weight="fill" /></button>
          </li>
        ))}
      </ul>
      <div className="sous-titre">Code SQL (déclencheur, CHECK…)</div>
      <ChampTexte etiquette="Code SQL de la contrainte" multiligne mono valeur={k.sql} onValider={(v) => maj((x) => { x.sql = v })} />
    </Section>
  )
}

function InspRegle({ m, id }: { m: Modele; id: string }) {
  const r = m.rules.find((x) => x.id === id)!
  const maj = (f: (x: typeof r) => void) => modifier((mm) => f(mm.rules.find((x) => x.id === id)!))
  return (
    <Section titre="Règle de gestion">
      <ChampTexte etiquette="Nom de la règle" valeur={r.name} onValider={(v) => maj((x) => { x.name = v.trim() })} autoFocusEvent />
      <div className="sous-titre">Description</div>
      <ChampTexte etiquette="Description de la règle" multiligne valeur={r.details} onValider={(v) => maj((x) => { x.details = v })} />
      <div className="sous-titre">Code SQL</div>
      <ChampTexte etiquette="Code SQL de la règle" multiligne mono valeur={r.sql} onValider={(v) => maj((x) => { x.sql = v })} />
      <div className="sous-titre">Éléments concernés</div>
      <ul className="liste-simple">
        {r.links.length === 0 && <li className="vide">Reliez-la avec l’outil Lien.</li>}
        {r.links.map((l, i) => (
          <li key={i}>{nomDe(m, cle(l))}<button className="icone-seule" title="Retirer ce lien" onClick={() => maj((x) => { x.links = x.links.filter((_, j) => j !== i) })}><Trash size={13} weight="fill" /></button></li>
        ))}
      </ul>
    </Section>
  )
}

function InspNote({ m, id }: { m: Modele; id: string }) {
  const n = m.notes.find((x) => x.id === id)!
  const maj = (f: (x: typeof n) => void) => modifier((mm) => f(mm.notes.find((x) => x.id === id)!))
  return (
    <Section titre="Texte">
      <div className="segmente" role="group" aria-label="Style">
        <button aria-pressed={n.style === 'texte'} onClick={() => maj((x) => { x.style = 'texte' })}>Texte</button>
        <button aria-pressed={n.style === 'titre'} onClick={() => maj((x) => { x.style = 'titre' })}>Titre</button>
      </div>
      <ChampTexte etiquette="Contenu du texte" multiligne valeur={n.text} onValider={(v) => maj((x) => { x.text = v })} autoFocusEvent />
    </Section>
  )
}

function InspFigure({ m, id }: { m: Modele; id: string }) {
  const f = m.figures.find((x) => x.id === id)!
  const maj = (g: (x: typeof f) => void) => modifier((mm) => g(mm.figures.find((x) => x.id === id)!))
  const trait = f.kind === 'line' || f.kind === 'arrow'
  return (
    <Section titre="Illustration">
      <Couleurs valeur={f.color} onChange={(c) => maj((x) => { x.color = c })} />
      {!trait && f.kind !== 'image' && <label className="case"><input type="checkbox" checked={f.isFilled} onChange={(e) => maj((x) => { x.isFilled = e.target.checked })} />Remplie</label>}
      <div className="deux-colonnes">
        <label className="ligne-champ verticale"><span>{trait ? 'Écart horizontal' : 'Largeur'}</span>
          <input className="champ" type="number" value={Math.round(trait ? f.span[0] : f.size[0])} onChange={(e) => maj((x) => { const v = Number(e.target.value) || 0; if (trait) x.span[0] = v; else x.size[0] = Math.max(16, v) })} /></label>
        <label className="ligne-champ verticale"><span>{trait ? 'Écart vertical' : 'Hauteur'}</span>
          <input className="champ" type="number" value={Math.round(trait ? f.span[1] : f.size[1])} onChange={(e) => maj((x) => { const v = Number(e.target.value) || 0; if (trait) x.span[1] = v; else x.size[1] = Math.max(16, v) })} /></label>
      </div>
    </Section>
  )
}

function Diagnostics({ m }: { m: Modele }) {
  const liste = useMemo(() => Moteur.verifier(m), [m])
  if (liste.length === 0) {
    return <p className="tout-va-bien"><CheckCircle size={16} weight="fill" /> Aucun problème détecté dans le MCD.</p>
  }
  return (
    <ul className="diagnostics">
      {liste.map((d, i) => (
        <li key={i} className={d.gravite}>
          <button className="lien-texte" disabled={!d.cible} onClick={() => d.cible && doc.selectionner([cle(d.cible)])}>
            {d.gravite === 'erreur' ? <XCircle size={15} weight="fill" /> : <WarningCircle size={15} weight="fill" />}
            <span>{d.message}</span>
          </button>
        </li>
      ))}
    </ul>
  )
}

export function Inspecteur() {
  const { modele, selection } = useDocument()
  const m = modele!
  const unique = selection.length === 1 ? selection[0] : null
  const existe = unique && m && [...m.entities, ...m.associations, ...m.inheritances, ...m.constraints, ...m.rules, ...m.notes, ...m.figures].some((x) => x.id === idDe(unique))

  let contenu: React.ReactNode
  if (selection.length > 1) {
    contenu = (
      <Section titre={`${selection.length} éléments sélectionnés`}>
        <ul className="liste-simple">{selection.slice(0, 12).map((c) => <li key={c}>{nomDe(m, c)}</li>)}</ul>
        <div className="actions-ligne">
          <button className="bouton" onClick={A.dupliquer}>Dupliquer</button>
          <button className="bouton danger" onClick={A.supprimerSelection}><Trash size={14} weight="fill" /> Supprimer</button>
        </div>
      </Section>
    )
  } else if (unique && existe) {
    const id = idDe(unique)
    switch (genreDe(unique)) {
      case 'entity': contenu = <InspEntite key={id} m={m} id={id} />; break
      case 'association': contenu = <InspAssociation key={id} m={m} id={id} />; break
      case 'inheritance': contenu = <InspHeritage key={id} m={m} id={id} />; break
      case 'constraint': contenu = <InspContrainte key={id} m={m} id={id} />; break
      case 'rule': contenu = <InspRegle key={id} m={m} id={id} />; break
      case 'note': contenu = <InspNote key={id} m={m} id={id} />; break
      case 'figure': contenu = <InspFigure key={id} m={m} id={id} />; break
    }
  } else {
    contenu = (
      <>
        <Section titre="Modèle">
          <dl className="chiffres">
            <div><dt>Entités</dt><dd>{m.entities.length}</dd></div>
            <div><dt>Associations</dt><dd>{m.associations.length}</dd></div>
            <div><dt>Propriétés</dt><dd>{m.entities.reduce((s, e) => s + e.attributes.length, 0) + m.associations.reduce((s, a) => s + a.attributes.length, 0)}</dd></div>
          </dl>
          <p className="aide"><PencilSimple size={12} weight="fill" /> Sélectionnez un élément pour modifier ses propriétés.</p>
        </Section>
        <Section titre="Vérification">
          <Diagnostics m={m} />
        </Section>
      </>
    )
  }
  return (
    <aside className="inspecteur" aria-label="Inspecteur">
      {contenu}
      {unique && existe && (
        <div className="insp-pied">
          <button className="bouton danger" onClick={() => doc.remplacer(Moteur.modifier(m, 'supprimer', { refs: [depuisCle(unique)] }).modele, [])}>
            <Trash size={14} weight="fill" /> Supprimer
          </button>
        </div>
      )}
    </aside>
  )
}
