// Export du diagramme affiché (MCD, MLD ou UML) en image SVG ou PNG.
// Les styles calculés sont recopiés dans le SVG : l'image reste juste hors de Cardinal.
import { doc } from '../modele/document'
import { ecrire } from '../modele/fichiers'

const PROPRIETES = [
  'fill', 'fill-opacity', 'stroke', 'stroke-opacity', 'stroke-width', 'stroke-dasharray', 'stroke-linecap', 'stroke-linejoin',
  'opacity', 'font-family', 'font-size', 'font-weight', 'font-style', 'letter-spacing', 'text-anchor', 'text-decoration',
  'dominant-baseline',
]

function contenuAffiche(): SVGGElement | null {
  return document.querySelector<SVGGElement>('.zone-principale svg > g')
}

/** L'image est toujours exportée en thème clair (documents, impression), quel que soit le thème affiché. */
export function construireSVG(fondPlein: boolean): { texte: string; largeur: number; hauteur: number } | null {
  const racine = document.documentElement
  const theme = racine.dataset.theme
  racine.dataset.theme = 'light'
  try {
    return construire(fondPlein)
  } finally {
    if (theme === undefined) delete racine.dataset.theme
    else racine.dataset.theme = theme
  }
}

function construire(fondPlein: boolean): { texte: string; largeur: number; hauteur: number } | null {
  const source = contenuAffiche()
  if (!source) return null
  // Le contenu dessiné (sans la poignée ni le lasso) et ses limites, en coordonnées du diagramme.
  const dessin = (source.querySelector('.diagramme, .mld, .uml') as SVGGElement | null) ?? source
  const boite = dessin.getBBox()
  if (boite.width === 0 || boite.height === 0) return null
  const marge = 24
  const largeur = Math.ceil(boite.width + marge * 2)
  const hauteur = Math.ceil(boite.height + marge * 2)

  const copie = dessin.cloneNode(true) as SVGGElement
  const originaux = [dessin, ...dessin.querySelectorAll('*')]
  const copies = [copie, ...copie.querySelectorAll('*')]
  originaux.forEach((orig, i) => {
    const style = getComputedStyle(orig)
    const cible = copies[i] as SVGElement
    const declarations = PROPRIETES.map((p) => `${p}:${style.getPropertyValue(p)}`).join(';')
    cible.setAttribute('style', declarations)
    cible.removeAttribute('class')
    cible.removeAttribute('data-cle')
  })
  // Le décalage d'une vue (UML) est conservé : on place le tout dans un groupe translaté.
  const transformation = dessin.getAttribute('transform') ?? ''
  const fond = getComputedStyle(document.documentElement).getPropertyValue('--papier').trim() || '#ffffff'
  const ns = 'http://www.w3.org/2000/svg'
  const svg = document.createElementNS(ns, 'svg')
  svg.setAttribute('xmlns', ns)
  svg.setAttribute('width', String(largeur))
  svg.setAttribute('height', String(hauteur))
  svg.setAttribute('viewBox', `0 0 ${largeur} ${hauteur}`)
  if (fondPlein) {
    const rect = document.createElementNS(ns, 'rect')
    rect.setAttribute('width', '100%')
    rect.setAttribute('height', '100%')
    rect.setAttribute('fill', fond)
    svg.appendChild(rect)
  }
  const groupe = document.createElementNS(ns, 'g')
  groupe.setAttribute('transform', `translate(${marge - boite.x},${marge - boite.y}) ${transformation}`)
  copie.removeAttribute('transform')
  groupe.appendChild(copie)
  svg.appendChild(groupe)
  return { texte: new XMLSerializer().serializeToString(svg), largeur, hauteur }
}

const NOMS: Record<string, string> = { mcd: 'MCD', mld: 'MLD', uml: 'UML' }

export async function exporterImage(format: 'svg' | 'png') {
  const { nom, onglet } = doc.etat
  if (onglet === 'sql') return
  const image = construireSVG(format === 'png')
  if (!image) {
    doc.informer('Rien à exporter : le diagramme est vide.', true)
    return
  }
  const base = `${nom} – ${NOMS[onglet]}`
  if (format === 'svg') {
    const r = await ecrire(image.texte, `${base}.svg`, [{ name: 'Image SVG', extensions: ['svg'] }])
    if (r) doc.informer('Image SVG exportée.')
    return
  }
  // PNG en double résolution, net sur les écrans haute densité et à l'impression.
  const echelle = 2
  const toile = document.createElement('canvas')
  toile.width = image.largeur * echelle
  toile.height = image.hauteur * echelle
  const contexte = toile.getContext('2d')!
  const img = new Image()
  img.src = `data:image/svg+xml;charset=utf-8,${encodeURIComponent(image.texte)}`
  await img.decode()
  contexte.scale(echelle, echelle)
  contexte.drawImage(img, 0, 0)
  const blob = await new Promise<Blob | null>((ok) => toile.toBlob(ok, 'image/png'))
  if (!blob) return
  const r = await ecrire(new Uint8Array(await blob.arrayBuffer()), `${base}.png`, [{ name: 'Image PNG', extensions: ['png'] }])
  if (r) doc.informer('Image PNG exportée.')
}
