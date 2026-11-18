// Onglets des vues (sous-modèles) au-dessus du canevas : « Modèle complet », puis chaque vue.
// Une vue montre une partie du modèle aux mêmes positions ; supprimer une vue ne supprime rien du modèle.
import { useState } from 'react'
import { DotsThreeCircle, PlusCircle, SquaresFour, Stack } from '@phosphor-icons/react'
import { doc, useDocument } from '../modele/document'
import { depuisCle, nouvelId, cle } from '../modele/refs'
import { Moteur } from '../moteur/moteur'
import { Menu } from './Menu'

export function OngletsVues() {
  const { modele, vue, selection } = useDocument()
  const m = modele!
  const [renomme, setRenomme] = useState<string | null>(null)
  const active = m.views.find((v) => v.id === vue)

  function creer() {
    let n = m.views.length + 1
    while (m.views.some((v) => v.name === `Vue ${n}`)) n++
    const refs = selection.length ? Moteur.modifier(m, 'completer', { refs: selection.map(depuisCle) }).refs : []
    const id = nouvelId()
    doc.modifier((mm) => { mm.views.push({ id, name: `Vue ${n}`, refs: refs.sort((a, b) => cle(a).localeCompare(cle(b))) }) })
    doc.regler({ vue: id })
    setRenomme(id)
  }

  function maj(id: string, f: (v: (typeof m.views)[number]) => void) {
    doc.modifier((mm) => { const v = mm.views.find((x) => x.id === id); if (v) f(v) })
  }

  return (
    <nav className="onglets-vues" aria-label="Vues du modèle">
      <div className="onglets-defilant">
        <button className="onglet-vue" aria-current={vue === null} onClick={() => doc.regler({ vue: null })}>
          <SquaresFour size={13} weight="fill" /> Modèle complet
        </button>
        {m.views.map((v) =>
          renomme === v.id ? (
            <input
              key={v.id} className="champ renommer-vue" autoFocus defaultValue={v.name} aria-label="Nom de la vue"
              onFocus={(e) => e.target.select()}
              onBlur={(e) => { const nom = e.target.value.trim(); if (nom && nom !== v.name) maj(v.id, (x) => { x.name = nom }); setRenomme(null) }}
              onKeyDown={(e) => { if (e.key === 'Enter') (e.target as HTMLInputElement).blur(); if (e.key === 'Escape') setRenomme(null) }}
            />
          ) : (
            <button key={v.id} className="onglet-vue" aria-current={vue === v.id} onClick={() => doc.regler({ vue: v.id })} onDoubleClick={() => setRenomme(v.id)} title="Double-cliquez pour renommer">
              <Stack size={13} weight="fill" /> {v.name}
            </button>
          ),
        )}
      </div>
      <button className="lien-action nouvelle-vue" onClick={creer}
        title={selection.length ? 'Créer une vue avec la sélection et ce qui la relie' : 'Créer une vue vide (ajoutez-y des éléments ensuite)'}>
        <PlusCircle size={15} weight="fill" /> Nouvelle vue
      </button>
      {active && (
        <Menu className="menu-vue" titre={`Gérer la vue « ${active.name} »`} elements={() => [
          { libelle: 'Renommer…', action: () => setRenomme(active.id) },
          {
            libelle: 'Ajouter la sélection à la vue', desactive: selection.length === 0,
            action: () => {
              const refs = Moteur.modifier(m, 'completer', { refs: selection.map(depuisCle) }).refs
              maj(active.id, (x) => { for (const r of refs) if (!x.refs.some((y) => cle(y) === cle(r))) x.refs.push(r) })
            },
          },
          {
            libelle: 'Retirer la sélection de la vue', desactive: selection.length === 0,
            action: () => { maj(active.id, (x) => { x.refs = x.refs.filter((r) => !selection.includes(cle(r))) }); doc.selectionner([]) },
          },
          { separateur: true, libelle: '' },
          {
            libelle: 'Supprimer la vue (les éléments restent dans le modèle)',
            action: () => { doc.modifier((mm) => { mm.views = mm.views.filter((x) => x.id !== active.id) }); doc.regler({ vue: null }) },
          },
        ]}>
          <DotsThreeCircle size={18} weight="fill" />
        </Menu>
      )}
    </nav>
  )
}
