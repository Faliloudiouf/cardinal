// Actions de fichier et d'édition partagées par le ruban, les menus et les raccourcis clavier.
import { Moteur, ErreurMoteur } from '../moteur/moteur'
import type { Modele } from '../moteur/types'
import { doc } from './document'
import { choisirEtLire, ecrire, estBureau, FILTRE_MODELES, lireChemin, noterRecent, oublierRecent, type FichierLu } from './fichiers'
import { depuisCle } from './refs'

function sansExtension(nom: string): string {
  return nom.replace(/\.(mcd|loo)$/i, '')
}

/** Demande confirmation avant de perdre des modifications non enregistrées (boîte native sur le bureau). */
export async function abandonnerModifications(): Promise<boolean> {
  if (!doc.etat.modele || !doc.etat.modifie) return true
  const question = `« ${doc.etat.nom} » contient des modifications non enregistrées. Les abandonner ?`
  if (estBureau) {
    const { ask } = await import('@tauri-apps/plugin-dialog')
    return ask(question, { title: 'Cardinal', kind: 'warning', okLabel: 'Abandonner', cancelLabel: 'Annuler' })
  }
  return window.confirm(question)
}

export async function nouveau() {
  if (!(await abandonnerModifications())) return
  doc.ouvrir(Moteur.vide(), 'Sans titre', null)
}

export async function ouvrirExemple(nom: 'entreprise' | 'scolarite') {
  if (!(await abandonnerModifications())) return
  doc.ouvrir(Moteur.exemple(nom), nom === 'scolarite' ? 'Exemple – Scolarité' : 'Exemple – Entreprise', null)
}

function charger(fichier: FichierLu) {
  const looping = /\.loo$/i.test(fichier.nom)
  try {
    const modele = Moteur.lire(fichier.octets, looping)
    // Un .loo garde son nom mais n'est jamais réécrit : il sera enregistré en .mcd.
    doc.ouvrir(modele, sansExtension(fichier.nom), looping ? null : fichier.chemin)
    if (fichier.chemin && !looping) noterRecent(fichier.chemin)
    if (looping) doc.informer('Modèle Looping importé. Il sera enregistré au format Cardinal (.mcd).')
  } catch (e) {
    doc.informer(e instanceof ErreurMoteur ? e.message : `Lecture impossible : ${String(e)}`, true)
  }
}

export async function ouvrir() {
  if (!(await abandonnerModifications())) return
  const fichier = await choisirEtLire(FILTRE_MODELES)
  if (fichier) charger(fichier)
}

/** Ouvre un fichier par son chemin (récents, double-clic dans l'explorateur de fichiers). */
export async function ouvrirChemin(chemin: string) {
  try {
    charger(await lireChemin(chemin))
  } catch {
    doc.informer(`Impossible de lire ${chemin}.`, true)
  }
}

export async function ouvrirRecent(chemin: string) {
  if (!(await abandonnerModifications())) return
  try {
    charger(await lireChemin(chemin))
  } catch {
    oublierRecent(chemin)
    doc.informer('Ce fichier n’existe plus à cet endroit. Il a été retiré des récents.', true)
  }
}

export async function enregistrer(sous = false) {
  const { modele, nom, chemin } = doc.etat
  if (!modele) return
  try {
    const texte = Moteur.encoder(modele)
    const resultat = await ecrire(texte, `${nom}.mcd`, [{ name: 'Modèle Cardinal', extensions: ['mcd'] }], sous ? null : chemin)
    if (!resultat) return
    doc.regler({ modifie: false, chemin: resultat.chemin, nom: sansExtension(resultat.nom) })
    if (resultat.chemin) noterRecent(resultat.chemin)
    doc.informer('Modèle enregistré.')
  } catch (e) {
    doc.informer(`Enregistrement impossible : ${String(e)}`, true)
  }
}

export async function exporterSQL() {
  const { modele, nom, sgbd } = doc.etat
  if (!modele) return
  const script = Moteur.sql(modele, sgbd)
  const resultat = await ecrire(script, `${nom}.sql`, [{ name: 'Script SQL', extensions: ['sql'] }])
  if (resultat) doc.informer(`Script ${sgbd} exporté.`)
}

export async function exporterXML() {
  const { modele, nom } = doc.etat
  if (!modele) return
  const resultat = await ecrire(Moteur.xml(modele), `${nom}.xml`, [{ name: 'MLD au format XML', extensions: ['xml'] }])
  if (resultat) doc.informer('MLD exporté au format XML.')
}

export async function copierSQL() {
  const { modele, sgbd } = doc.etat
  if (!modele) return
  try {
    await navigator.clipboard.writeText(Moteur.sql(modele, sgbd))
    doc.regler({ copie: true })
    setTimeout(() => doc.regler({ copie: false }), 1600)
  } catch {
    doc.informer('Le presse-papiers n’est pas accessible.', true)
  }
}

export async function importerSQL() {
  if (!(await abandonnerModifications())) return
  const fichier = await choisirEtLire([{ name: 'Script SQL', extensions: ['sql', 'txt'] }])
  if (!fichier) return
  try {
    const modele = Moteur.retro(new TextDecoder().decode(fichier.octets))
    doc.ouvrir(modele, fichier.nom.replace(/\.(sql|txt)$/i, ''), null, true)
    doc.informer('MCD reconstruit à partir du script SQL.')
  } catch (e) {
    doc.informer(e instanceof ErreurMoteur ? e.message : String(e), true)
  }
}

// Édition

export function supprimerSelection() {
  const { modele, selection } = doc.etat
  if (!modele || selection.length === 0) return
  const { modele: suite } = Moteur.modifier(modele, 'supprimer', { refs: selection.map(depuisCle) })
  doc.remplacer(suite, [])
}

let pressePapiers: Modele | null = null

export function copier() {
  const { modele, selection } = doc.etat
  if (!modele || selection.length === 0) return
  pressePapiers = Moteur.modifier(modele, 'copier', { refs: selection.map(depuisCle) }).modele
}

export function couper() {
  copier()
  supprimerSelection()
}

export function coller() {
  const modele = doc.etat.modele
  if (!modele || !pressePapiers) return
  const { modele: suite, refs } = Moteur.modifier(modele, 'coller', { fragment: pressePapiers })
  doc.remplacer(suite, refs.map((r) => {
    const genre = Object.keys(r)[0] as keyof typeof r
    return `${genre}:${r[genre]!._0}`
  }))
}

export function dupliquer() {
  copier()
  coller()
}

export function toutSelectionner() {
  const m = doc.etat.modele
  if (!m) return
  doc.selectionner([
    ...m.entities.map((e) => `entity:${e.id}`), ...m.associations.map((e) => `association:${e.id}`),
    ...m.inheritances.map((e) => `inheritance:${e.id}`), ...m.constraints.map((e) => `constraint:${e.id}`),
    ...m.rules.map((e) => `rule:${e.id}`), ...m.notes.map((e) => `note:${e.id}`), ...m.figures.map((e) => `figure:${e.id}`),
  ])
}
