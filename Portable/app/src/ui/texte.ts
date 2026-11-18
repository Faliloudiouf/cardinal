// Mesure du texte affiché, pour couper proprement (« … ») ce qui ne tient pas dans une boîte.
const toile = typeof document !== 'undefined' ? document.createElement('canvas').getContext('2d') : null
const cache = new Map<string, number>()

export function largeur(texte: string, taille: number, graisse = 400, mono = false): number {
  const police = `${graisse} ${taille}px ${mono ? "'JetBrains Mono', monospace" : "'Inter', system-ui, sans-serif"}`
  const cle = `${police}|${texte}`
  const connu = cache.get(cle)
  if (connu !== undefined) return connu
  if (!toile) return texte.length * taille * 0.6
  toile.font = police
  const mesure = toile.measureText(texte).width
  if (cache.size > 5000) cache.clear()
  cache.set(cle, mesure)
  return mesure
}

export function tronquer(texte: string, max: number, taille: number, graisse = 400, mono = false): string {
  if (largeur(texte, taille, graisse, mono) <= max) return texte
  let bas = 0
  let haut = texte.length
  while (bas < haut) {
    const milieu = Math.ceil((bas + haut) / 2)
    if (largeur(texte.slice(0, milieu) + '…', taille, graisse, mono) <= max) bas = milieu
    else haut = milieu - 1
  }
  return texte.slice(0, bas).trimEnd() + '…'
}

/** Découpe un texte en lignes qui tiennent dans `max` pixels (retours à la ligne conservés). */
export function lignes(texte: string, max: number, taille: number, graisse = 400): string[] {
  const resultat: string[] = []
  for (const paragraphe of texte.split('\n')) {
    let ligne = ''
    for (const mot of paragraphe.split(/(\s+)/)) {
      const essai = ligne + mot
      if (ligne && largeur(essai.trimEnd(), taille, graisse) > max) {
        resultat.push(ligne.trimEnd())
        ligne = mot.trimStart()
      } else {
        ligne = essai
      }
    }
    resultat.push(ligne.trimEnd())
  }
  return resultat
}
