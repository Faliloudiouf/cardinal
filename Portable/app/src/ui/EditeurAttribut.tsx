// Fenêtre « Propriété », comme sur Mac et dans Looping : nom, famille et type, paramètres,
// aperçu du SQL produit pour chaque SGBD, propriétés SQL, commentaire. Rien n'est appliqué avant OK.
import { useEffect, useMemo, useRef, useState } from 'react'
import { Key, Plus, MinusCircle, WarningCircle, XCircle } from '@phosphor-icons/react'
import { Moteur } from '../moteur/moteur'
import { SGBD, type Attribut, type TypeInfo } from '../moteur/types'

let catalogue: TypeInfo[] | null = null
export function types(): TypeInfo[] {
  return (catalogue ??= Moteur.types())
}

const FAMILLES = [
  { id: 'texte', libelle: 'Texte', defaut: 'varchar' },
  { id: 'numerique', libelle: 'Numérique', defaut: 'int' },
  { id: 'dateHeure', libelle: 'Date / Heure', defaut: 'date' },
  { id: 'autre', libelle: 'Autre', defaut: 'boolean' },
] as const

const ENCODAGES = [
  { id: 'ascii', libelle: 'ASCII' }, { id: 'unicode', libelle: 'Unicode' }, { id: 'binaire', libelle: 'Binaire' },
] as const
const STOCKAGES = [
  { id: 'variable', libelle: 'Variable' }, { id: 'fixe', libelle: 'Fixe' }, { id: 'volumineux', libelle: 'Volumineux' },
] as const

function typeTexte(encodage: string, stockage: string): string {
  return types().find((t) => t.encodage === encodage && t.stockage === stockage)?.id ?? 'varchar'
}

export function EditeurAttribut({ attribut, identifiantPossible, onValider, onFermer }: {
  attribut: Attribut
  identifiantPossible: boolean
  onValider: (a: Attribut) => void
  onFermer: () => void
}) {
  const [brouillon, setBrouillon] = useState(attribut)
  const analyse = useMemo(() => Moteur.attribut(brouillon), [brouillon])
  const info = types().find((t) => t.id === brouillon.type) ?? types()[0]
  const dialogue = useRef<HTMLDialogElement>(null)

  useEffect(() => {
    dialogue.current?.showModal()
  }, [])

  const changer = (champs: Partial<Attribut>) => setBrouillon((b) => ({ ...b, ...champs }))
  const changerType = (type: string) => setBrouillon((b) => Moteur.attribut(b, type).attribut)

  function valider() {
    onValider(Moteur.attribut(brouillon, undefined, true).attribut)
  }

  const nomVide = brouillon.name.trim() === ''

  return (
    <dialog ref={dialogue} className="dialogue editeur-attribut" onClose={onFermer} onCancel={onFermer} aria-labelledby="titre-propriete">
      <form method="dialog" onSubmit={(e) => { e.preventDefault(); if (!nomVide) valider() }}>
        <header className="dialogue-entete">
          <h2 id="titre-propriete">Propriété</h2>
          <code className="apercu-type">{analyse.affichage}</code>
        </header>
        <div className="dialogue-corps">
          <fieldset className="section">
            <legend>Nom</legend>
            <label className="ligne-champ">
              <span>Nom</span>
              <input className="champ" autoFocus value={brouillon.name} placeholder="nom_de_la_propriete" onChange={(e) => changer({ name: e.target.value })} />
            </label>
            <label className="ligne-champ">
              <span>Nom logique</span>
              <input className="champ" value={brouillon.label} placeholder="facultatif" onChange={(e) => changer({ label: e.target.value })} />
            </label>
          </fieldset>

          <fieldset className="section">
            <legend>Type</legend>
            <div className="segmente large" role="group" aria-label="Famille de types">
              {FAMILLES.map((f) => (
                <button type="button" key={f.id} aria-pressed={info.categorie === f.id} onClick={() => info.categorie !== f.id && changerType(f.defaut)}>{f.libelle}</button>
              ))}
            </div>

            {info.categorie === 'texte' && (
              <>
                <div className="ligne-champ">
                  <span>Jeu de caractères</span>
                  <div className="segmente" role="group" aria-label="Jeu de caractères">
                    {ENCODAGES.map((e) => (
                      <button type="button" key={e.id} aria-pressed={info.encodage === e.id} onClick={() => changerType(typeTexte(e.id, info.stockage ?? 'variable'))}>{e.libelle}</button>
                    ))}
                  </div>
                </div>
                <div className="ligne-champ">
                  <span>Stockage</span>
                  <div className="segmente" role="group" aria-label="Stockage">
                    {STOCKAGES.map((s) => (
                      <button type="button" key={s.id} aria-pressed={info.stockage === s.id} onClick={() => changerType(typeTexte(info.encodage ?? 'ascii', s.id))}>{s.libelle}</button>
                    ))}
                  </div>
                </div>
              </>
            )}
            {info.categorie !== 'texte' && (
              <div className="choix-types" role="radiogroup" aria-label="Type">
                {types().filter((t) => t.categorie === info.categorie).map((t) => (
                  <label key={t.id} className="case">
                    <input type="radio" name="type" checked={brouillon.type === t.id} onChange={() => changerType(t.id)} />
                    {t.libelle}
                  </label>
                ))}
              </div>
            )}
            {info.longueur && (
              <label className="ligne-champ">
                <span>Longueur</span>
                <input className="champ court" type="number" min={1} max={info.longueurMax} value={brouillon.length}
                  onChange={(e) => changer({ length: Math.min(info.longueurMax, Math.max(1, Number(e.target.value) || 1)) })} />
              </label>
            )}
            {info.precision && (
              <div className="deux-colonnes">
                <label className="ligne-champ">
                  <span>Précision</span>
                  <input className="champ court" type="number" min={1} max={38} value={brouillon.precision}
                    onChange={(e) => {
                      const p = Math.min(38, Math.max(1, Number(e.target.value) || 1))
                      changer({ precision: p, scale: Math.min(brouillon.scale, p) })
                    }} />
                </label>
                <label className="ligne-champ">
                  <span>Échelle</span>
                  <input className="champ court" type="number" min={0} max={brouillon.precision} value={brouillon.scale}
                    onChange={(e) => changer({ scale: Math.min(brouillon.precision, Math.max(0, Number(e.target.value) || 0)) })} />
                </label>
              </div>
            )}
            {brouillon.type === 'enum' && (
              <div className="valeurs-enum">
                <span className="sous-titre">Valeurs autorisées</span>
                {brouillon.enumValues.map((v, i) => (
                  <div key={i} className="valeur-enum">
                    <input className="champ" value={v} aria-label={`Valeur ${i + 1}`}
                      onChange={(e) => changer({ enumValues: brouillon.enumValues.map((x, j) => (j === i ? e.target.value : x)) })} />
                    <button type="button" className="icone-seule" title="Retirer cette valeur"
                      onClick={() => changer({ enumValues: brouillon.enumValues.filter((_, j) => j !== i) })}>
                      <MinusCircle size={18} weight="fill" />
                    </button>
                  </div>
                ))}
                <button type="button" className="lien-action" onClick={() => changer({ enumValues: [...brouillon.enumValues, ''] })}>
                  <Plus size={14} weight="bold" /> Ajouter une valeur
                </button>
              </div>
            )}
            {brouillon.type === 'libre' && (
              <label className="ligne-champ">
                <span>Type SQL</span>
                <input className="champ mono" value={brouillon.customType} placeholder="ex. CITEXT, INET, YEAR" onChange={(e) => changer({ customType: e.target.value })} />
              </label>
            )}
            {info.collation && (
              <label className="ligne-champ">
                <span>Collation</span>
                <input className="champ" value={brouillon.collation} placeholder="facultatif (ex. utf8mb4_bin)" onChange={(e) => changer({ collation: e.target.value })} />
              </label>
            )}
            <p className="aide">{info.aide}</p>
          </fieldset>

          <fieldset className="section">
            <legend>SQL généré pour chaque SGBD</legend>
            <dl className="apercu-sql">
              {SGBD.map((s) => (
                <div key={s}><dt>{s}</dt><dd className="mono">{analyse.apercu[s]}</dd></div>
              ))}
            </dl>
          </fieldset>

          {analyse.problemes.length > 0 && (
            <ul className="problemes">
              {analyse.problemes.map((p) => (
                <li key={p.texte} className={p.erreur ? 'erreur' : 'avertissement'}>
                  {p.erreur ? <XCircle size={16} weight="fill" /> : <WarningCircle size={16} weight="fill" />}
                  {p.texte}
                </li>
              ))}
            </ul>
          )}

          <fieldset className="section">
            <legend>Propriétés</legend>
            <div className="cases">
              {identifiantPossible && (
                <label className="case"><input type="checkbox" checked={brouillon.isIdentifier} onChange={(e) => changer({ isIdentifier: e.target.checked })} /><Key size={13} weight="fill" /> Identifiant</label>
              )}
              <label className="case"><input type="checkbox" disabled={brouillon.isIdentifier} checked={brouillon.isNotNull} onChange={(e) => changer({ isNotNull: e.target.checked })} />NOT NULL</label>
              <label className="case"><input type="checkbox" disabled={brouillon.isIdentifier} checked={brouillon.isUnique} onChange={(e) => changer({ isUnique: e.target.checked })} />UNIQUE</label>
            </div>
            <label className="ligne-champ">
              <span>Complément</span>
              <input className="champ mono" value={brouillon.complement} placeholder="ex. DEFAULT 0" title="Texte SQL ajouté tel quel à la colonne" onChange={(e) => changer({ complement: e.target.value })} />
            </label>
          </fieldset>

          <fieldset className="section">
            <legend>Commentaire</legend>
            <textarea className="champ" rows={2} value={brouillon.comment} aria-label="Commentaire" onChange={(e) => changer({ comment: e.target.value })} />
          </fieldset>
        </div>
        <footer className="dialogue-pied">
          <button type="button" className="bouton" onClick={onFermer}>Annuler</button>
          <button type="submit" className="bouton principal" disabled={nomVide}>OK</button>
        </footer>
      </form>
    </dialog>
  )
}
