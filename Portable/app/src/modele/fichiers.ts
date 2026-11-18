// Fichiers : boîtes de dialogue natives sous Windows et Linux (Tauri), simple
// sélection / téléchargement dans un navigateur. Le reste de l'interface ne voit pas la différence.

export const estBureau = typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window

export interface FichierLu {
  nom: string
  chemin: string | null
  octets: Uint8Array
}

export interface Filtre { name: string; extensions: string[] }

export const FILTRE_MODELES: Filtre[] = [{ name: 'Modèles Cardinal ou Looping', extensions: ['mcd', 'loo'] }]

function nomDepuisChemin(chemin: string): string {
  return chemin.split(/[\\/]/).pop() ?? chemin
}

export async function choisirEtLire(filtres: Filtre[]): Promise<FichierLu | null> {
  if (estBureau) {
    const { open } = await import('@tauri-apps/plugin-dialog')
    const chemin = await open({ multiple: false, directory: false, filters: filtres })
    if (!chemin || Array.isArray(chemin)) return null
    return lireChemin(chemin)
  }
  return new Promise((resolve) => {
    const champ = document.createElement('input')
    champ.type = 'file'
    champ.accept = filtres.flatMap((f) => f.extensions.map((e) => `.${e}`)).join(',')
    champ.onchange = async () => {
      const fichier = champ.files?.[0]
      if (!fichier) return resolve(null)
      resolve({ nom: fichier.name, chemin: null, octets: new Uint8Array(await fichier.arrayBuffer()) })
    }
    champ.addEventListener('cancel', () => resolve(null))
    champ.click()
  })
}

export async function lireChemin(chemin: string): Promise<FichierLu> {
  const { readFile } = await import('@tauri-apps/plugin-fs')
  return { nom: nomDepuisChemin(chemin), chemin, octets: await readFile(chemin) }
}

/**
 * Écrit un fichier. Avec un chemin connu (bureau) : écrit directement. Sinon : demande où
 * l'enregistrer (bureau) ou le télécharge (navigateur). Renvoie le chemin choisi, ou null si annulé.
 */
export async function ecrire(
  contenu: string | Uint8Array,
  nomPropose: string,
  filtres: Filtre[],
  chemin: string | null = null,
): Promise<{ chemin: string | null; nom: string } | null> {
  const octets = typeof contenu === 'string' ? new TextEncoder().encode(contenu) : contenu
  if (estBureau) {
    let cible = chemin
    if (!cible) {
      const { save } = await import('@tauri-apps/plugin-dialog')
      cible = await save({ defaultPath: nomPropose, filters: filtres })
      if (!cible) return null
      const extension = filtres[0]?.extensions[0]
      if (extension && !cible.toLowerCase().endsWith(`.${extension}`)) cible += `.${extension}`
    }
    const { writeFile } = await import('@tauri-apps/plugin-fs')
    await writeFile(cible, octets)
    return { chemin: cible, nom: nomDepuisChemin(cible) }
  }
  const lien = document.createElement('a')
  lien.href = URL.createObjectURL(new Blob([octets as BlobPart]))
  lien.download = nomPropose
  lien.click()
  setTimeout(() => URL.revokeObjectURL(lien.href), 2000)
  return { chemin: null, nom: nomPropose }
}

// Fichiers récents (bureau seulement : un navigateur ne peut pas rouvrir un chemin).

export interface Recent { chemin: string; nom: string; date: number }
const CLE_RECENTS = 'cardinal.recents'

export function recents(): Recent[] {
  try {
    const liste = JSON.parse(localStorage.getItem(CLE_RECENTS) ?? '[]') as Recent[]
    return Array.isArray(liste) ? liste.filter((r) => typeof r.chemin === 'string').slice(0, 10) : []
  } catch {
    return []
  }
}

export function noterRecent(chemin: string) {
  try {
    const liste = [{ chemin, nom: nomDepuisChemin(chemin), date: Date.now() }, ...recents().filter((r) => r.chemin !== chemin)]
    localStorage.setItem(CLE_RECENTS, JSON.stringify(liste.slice(0, 10)))
  } catch { /* stockage indisponible : on se passe des récents */ }
}

export function oublierRecent(chemin: string) {
  try {
    localStorage.setItem(CLE_RECENTS, JSON.stringify(recents().filter((r) => r.chemin !== chemin)))
  } catch { /* rien à faire */ }
}
