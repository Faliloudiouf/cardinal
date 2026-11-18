import { useSyncExternalStore } from 'react'
import type { Modele, Sgbd } from '../moteur/types'

export type Onglet = 'mcd' | 'mld' | 'uml' | 'sql'
export type Outil =
  | 'selection' | 'entite' | 'association' | 'heritage' | 'contrainte' | 'cif' | 'regle' | 'note' | 'lien'
  | 'rectangle' | 'ellipse' | 'trait' | 'fleche'

export interface Etat {
  /** null : écran d'accueil. */
  modele: Modele | null
  nom: string
  chemin: string | null
  modifie: boolean
  selection: string[]
  onglet: Onglet
  outil: Outil
  vue: string | null
  /** Premier élément cliqué avec l'outil Lien, en attente du second. */
  attente: string | null
  /** Zoom du canevas (1 = 100 %). */
  zoom: number
  umlSimplifie: boolean
  /** Le script SQL vient d'être copié (le bouton affiche « Copié »). */
  copie: boolean
  sgbd: Sgbd
  peutAnnuler: boolean
  peutRetablir: boolean
  /** Message bref en bas de la fenêtre (« Enregistré », erreur de lecture…). */
  message: { texte: string; erreur: boolean } | null
}

const LIMITE_HISTORIQUE = 200

function lireSgbd(): Sgbd {
  try { return (localStorage.getItem('cardinal.sgbd') as Sgbd) || 'PostgreSQL' } catch { return 'PostgreSQL' }
}

class Document {
  etat: Etat = {
    modele: null, nom: 'Sans titre', chemin: null, modifie: false, selection: [], onglet: 'mcd', outil: 'selection',
    vue: null, attente: null, zoom: 1, umlSimplifie: false, copie: false, sgbd: lireSgbd(), peutAnnuler: false, peutRetablir: false, message: null,
  }
  private passe: Modele[] = []
  private futur: Modele[] = []
  private avantGeste: Modele | null = null
  private abonnes = new Set<() => void>()
  private minuterieMessage = 0

  abonner = (f: () => void) => {
    this.abonnes.add(f)
    return () => this.abonnes.delete(f)
  }

  private publier(changes: Partial<Etat>) {
    this.etat = { ...this.etat, ...changes, peutAnnuler: this.passe.length > 0, peutRetablir: this.futur.length > 0 }
    this.abonnes.forEach((f) => f())
  }

  /** Ouvre un modèle (nouveau, lu sur disque, exemple) : l'historique repart de zéro. */
  ouvrir(modele: Modele, nom: string, chemin: string | null, modifie = false) {
    this.passe = []
    this.futur = []
    this.publier({ modele, nom, chemin, modifie, selection: [], onglet: 'mcd', outil: 'selection', vue: null, attente: null })
  }

  fermer() {
    this.passe = []
    this.futur = []
    this.publier({ modele: null, selection: [], modifie: false, chemin: null, nom: 'Sans titre' })
  }

  /** Modification annulable : la recette reçoit une copie du modèle et la modifie. */
  modifier(recette: (m: Modele) => void, selection?: string[]) {
    const actuel = this.etat.modele
    if (!actuel) return
    const copie = structuredClone(actuel)
    recette(copie)
    this.remplacer(copie, selection)
  }

  remplacer(modele: Modele, selection?: string[]) {
    if (!this.etat.modele) return
    this.passe.push(this.avantGeste ?? this.etat.modele)
    if (this.passe.length > LIMITE_HISTORIQUE) this.passe.shift()
    this.futur = []
    this.avantGeste = null
    this.publier({ modele, modifie: true, ...(selection ? { selection } : {}) })
  }

  // Gestes continus (glisser) : un seul pas d'annulation pour tout le geste.
  debutGeste() {
    this.avantGeste = this.etat.modele
  }

  pendantGeste(modele: Modele) {
    this.publier({ modele })
  }

  finGeste() {
    if (this.avantGeste && this.avantGeste !== this.etat.modele) {
      this.passe.push(this.avantGeste)
      if (this.passe.length > LIMITE_HISTORIQUE) this.passe.shift()
      this.futur = []
      this.avantGeste = null
      this.publier({ modifie: true })
    }
    this.avantGeste = null
  }

  annuler() {
    const precedent = this.passe.pop()
    if (!precedent || !this.etat.modele) return
    this.futur.push(this.etat.modele)
    this.publier({ modele: precedent, modifie: true, selection: this.selectionValide(precedent) })
  }

  retablir() {
    const suivant = this.futur.pop()
    if (!suivant || !this.etat.modele) return
    this.passe.push(this.etat.modele)
    this.publier({ modele: suivant, modifie: true, selection: this.selectionValide(suivant) })
  }

  private selectionValide(m: Modele): string[] {
    const ids = new Set([
      ...m.entities, ...m.associations, ...m.inheritances, ...m.constraints, ...m.rules, ...m.notes, ...m.figures,
    ].map((e) => e.id))
    return this.etat.selection.filter((c) => ids.has(c.split(':')[1]))
  }

  selectionner(selection: string[]) {
    this.publier({ selection })
  }

  regler(changes: Partial<Pick<Etat, 'onglet' | 'outil' | 'vue' | 'sgbd' | 'nom' | 'chemin' | 'modifie' | 'attente' | 'zoom' | 'umlSimplifie' | 'copie'>>) {
    if (changes.sgbd) try { localStorage.setItem('cardinal.sgbd', changes.sgbd) } catch { /* sans effet */ }
    this.publier(changes)
  }

  informer(texte: string, erreur = false) {
    window.clearTimeout(this.minuterieMessage)
    this.publier({ message: { texte, erreur } })
    this.minuterieMessage = window.setTimeout(() => this.publier({ message: null }), erreur ? 6000 : 2600)
  }
}

export const doc = new Document()

export function useDocument(): Etat {
  return useSyncExternalStore(doc.abonner, () => doc.etat)
}
