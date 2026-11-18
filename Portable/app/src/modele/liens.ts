// Relier deux éléments avec l'outil Lien : mêmes règles que la version Mac (DiagramView.Linker).
import type { Modele } from '../moteur/types'
import { genreDe, idDe, nouvelId, ref, depuisCle, cle } from './refs'

/** Pivot : élément auquel on peut enchaîner plusieurs liens (association, héritage, contrainte, règle). */
export function estPivot(c: string): boolean {
  return !['entity', 'note', 'figure'].includes(genreDe(c))
}

export function pivot(a: string, b: string): string {
  return estPivot(a) ? a : b
}

/** Relie a et b (dans un sens ou dans l'autre). Renvoie faux si ce lien n'a pas de sens. */
export function relier(a: string, b: string, m: Modele): boolean {
  return connecter(a, b, m) || connecter(b, a, m)
}

function connecter(a: string, b: string, m: Modele): boolean {
  const ga = genreDe(a)
  const gb = genreDe(b)
  if (ga === 'entity' && gb === 'association') {
    const asso = m.associations.find((x) => x.id === idDe(b))
    if (!asso) return false
    asso.legs.push({ id: nouvelId(), entityID: idDe(a), cardinality: '0,N', isRelative: false, role: '' })
    return true
  }
  if (ga === 'entity' && gb === 'inheritance') {
    const h = m.inheritances.find((x) => x.id === idDe(b))
    if (!h) return false
    const e = idDe(a)
    if (!h.parentID && !h.childIDs.includes(e)) h.parentID = e
    else if (h.parentID !== e && !h.childIDs.includes(e)) h.childIDs.push(e)
    else return false
    return true
  }
  if (ga === 'constraint') {
    const k = m.constraints.find((x) => x.id === idDe(a))
    if (!k || !['entity', 'association', 'inheritance'].includes(gb)) return false
    if (k.links.some((l) => cle(l.target) === b)) return false
    const lien = { id: nouvelId(), target: depuisCle(b), isTarget: false }
    if (gb === 'entity' && k.kind === 'CIF' && !k.links.some((l) => l.isTarget)) lien.isTarget = true
    k.links.push(lien)
    return true
  }
  if (ga === 'rule') {
    const r = m.rules.find((x) => x.id === idDe(a))
    if (!r || gb === 'rule' || r.links.some((l) => cle(l) === b)) return false
    r.links.push(ref(gb, idDe(b)))
    return true
  }
  return false
}
