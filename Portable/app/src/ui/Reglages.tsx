// Réglages : apparence de l'application (comme sur Mac : Automatique, Clair, Sombre)
// et options du modèle ouvert (nommage, clés étrangères, libellés).
import { useEffect, useRef, useState } from 'react'
import { doc, useDocument } from '../modele/document'
import type { Reglages as R } from '../moteur/types'

export type Apparence = 'auto' | 'clair' | 'sombre'

export function lireApparence(): Apparence {
  try {
    const v = localStorage.getItem('cardinal.apparence')
    return v === 'clair' || v === 'sombre' ? v : 'auto'
  } catch {
    return 'auto'
  }
}

export function appliquerApparence(a: Apparence) {
  const racine = document.documentElement
  if (a === 'auto') delete racine.dataset.theme
  else racine.dataset.theme = a === 'sombre' ? 'dark' : 'light'
  try { localStorage.setItem('cardinal.apparence', a) } catch { /* sans effet */ }
  window.dispatchEvent(new CustomEvent('cardinal:apparence', { detail: a }))
}

export function ChoixApparence() {
  const [valeur, setValeur] = useState(lireApparence)
  useEffect(() => {
    const f = (e: Event) => setValeur((e as CustomEvent<Apparence>).detail)
    window.addEventListener('cardinal:apparence', f)
    return () => window.removeEventListener('cardinal:apparence', f)
  }, [])
  return (
    <div className="segmente" role="group" aria-label="Apparence">
      {([['auto', 'Automatique'], ['clair', 'Clair'], ['sombre', 'Sombre']] as const).map(([v, l]) => (
        <button key={v} aria-pressed={valeur === v} onClick={() => appliquerApparence(v)}>{l}</button>
      ))}
    </div>
  )
}

const NOMMAGES: [R['naming'], string][] = [
  ['telQuel', 'Tel quel'], ['snake', 'snake_case'], ['camel', 'camelCase'], ['pascal', 'PascalCase'], ['majuscules', 'MAJUSCULES'],
]

export function Reglages({ onFermer }: { onFermer: () => void }) {
  const { modele } = useDocument()
  const dialogue = useRef<HTMLDialogElement>(null)
  useEffect(() => { dialogue.current?.showModal() }, [])
  const s = modele?.settings
  const regler = <K extends keyof R>(cle: K, v: R[K]) => doc.modifier((m) => { m.settings[cle] = v })

  return (
    <dialog ref={dialogue} className="dialogue reglages" onClose={onFermer} onCancel={onFermer} aria-labelledby="titre-reglages">
      <header className="dialogue-entete"><h2 id="titre-reglages">Réglages</h2></header>
      <div className="dialogue-corps">
        <fieldset className="section">
          <legend>Général</legend>
          <div className="ligne-champ"><span>Apparence</span><ChoixApparence /></div>
          <p className="aide">Automatique suit le thème clair ou sombre du système.</p>
        </fieldset>
        {s && (
          <fieldset className="section">
            <legend>Modèle ouvert</legend>
            <label className="ligne-champ">
              <span>Noms des tables et colonnes</span>
              <select className="champ" value={s.naming} onChange={(e) => regler('naming', e.target.value as R['naming'])}>
                {NOMMAGES.map(([v, l]) => <option key={v} value={v}>{l}</option>)}
              </select>
            </label>
            <label className="case"><input type="checkbox" checked={s.useLabels} onChange={(e) => regler('useLabels', e.target.checked)} />Nommer les colonnes avec les noms logiques (comme Looping)</label>
            <label className="case"><input type="checkbox" checked={s.foreignKeysAtEnd} onChange={(e) => regler('foreignKeysAtEnd', e.target.checked)} />Clés étrangères en fin de script (ALTER TABLE)</label>
          </fieldset>
        )}
      </div>
      <footer className="dialogue-pied"><button className="bouton principal" onClick={onFermer}>Fermer</button></footer>
    </dialog>
  )
}
