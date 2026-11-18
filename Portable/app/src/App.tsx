import { useEffect, useState } from 'react'
import { WarningCircle } from '@phosphor-icons/react'
import { chargerMoteur, Moteur } from './moteur/moteur'
import { doc, useDocument } from './modele/document'
import * as A from './modele/actions'
import { estBureau } from './modele/fichiers'
import { Accueil } from './ui/Accueil'
import { Canevas, commandesCanevas, ZOOM_MAX, ZOOM_MIN } from './ui/Canevas'
import { Inspecteur } from './ui/Inspecteur'
import { OngletsVues } from './ui/OngletsVues'
import { Ruban } from './ui/Ruban'
import { Reglages, appliquerApparence, lireApparence } from './ui/Reglages'
import { VueMLD, VueSQL, VueUML } from './ui/Vues'

function champActif(): boolean {
  const el = document.activeElement
  return !!el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.tagName === 'SELECT' || (el as HTMLElement).isContentEditable)
}

function raccourcis(e: KeyboardEvent, ouvrirReglages: () => void) {
  const mod = e.ctrlKey || e.metaKey
  const etat = doc.etat
  const k = e.key.toLowerCase()
  if (mod && k === 'n') { e.preventDefault(); A.nouveau(); return }
  if (mod && k === 'o') { e.preventDefault(); A.ouvrir(); return }
  if (mod && e.key === ',') { e.preventDefault(); ouvrirReglages(); return }
  if (!etat.modele) return
  if (mod && k === 's') { e.preventDefault(); A.enregistrer(e.shiftKey); return }
  if (mod && ['1', '2', '3', '4'].includes(e.key)) {
    e.preventDefault()
    doc.regler({ onglet: (['mcd', 'mld', 'uml', 'sql'] as const)[Number(e.key) - 1] })
    return
  }
  if (mod && (e.key === '+' || e.key === '=')) { e.preventDefault(); doc.regler({ zoom: Math.min(ZOOM_MAX, etat.zoom * 1.2) }); return }
  if (mod && e.key === '-') { e.preventDefault(); doc.regler({ zoom: Math.max(ZOOM_MIN, etat.zoom / 1.2) }); return }
  if (mod && e.key === '0') { e.preventDefault(); doc.regler({ zoom: 1 }); return }
  if (mod && e.key === '9') { e.preventDefault(); commandesCanevas.ajuster(); return }
  if (champActif()) return
  if (mod && k === 'z') { e.preventDefault(); if (e.shiftKey) doc.retablir(); else doc.annuler(); return }
  if (mod && k === 'y') { e.preventDefault(); doc.retablir(); return }
  if (etat.onglet !== 'mcd') return
  if (mod && k === 'a') { e.preventDefault(); A.toutSelectionner(); return }
  if (mod && k === 'c') { A.copier(); return }
  if (mod && k === 'x') { A.couper(); return }
  if (mod && k === 'v') { A.coller(); return }
  if (mod && k === 'd') { e.preventDefault(); A.dupliquer(); return }
  if (e.key === 'Delete' || e.key === 'Backspace') { e.preventDefault(); A.supprimerSelection(); return }
  if (e.key === 'Escape') { doc.regler({ outil: 'selection', attente: null }); if (etat.outil === 'selection') doc.selectionner([]); return }
  if (!mod && !e.altKey) {
    const outils: Record<string, typeof etat.outil> = { e: 'entite', a: 'association', l: 'lien', h: 'heritage', t: 'note', v: 'selection' }
    if (outils[k]) doc.regler({ outil: outils[k], attente: null })
  }
}

function Editeur({ ouvrirReglages }: { ouvrirReglages: () => void }) {
  const etat = useDocument()
  const titre = `${etat.nom}${etat.modifie ? ' — modifié' : ''}`
  useEffect(() => {
    document.title = `${etat.nom}${etat.modifie ? ' •' : ''} — Cardinal`
    if (estBureau) import('@tauri-apps/api/window').then(({ getCurrentWindow }) => getCurrentWindow().setTitle(`${etat.nom}${etat.modifie ? ' •' : ''} — Cardinal`)).catch(() => {})
  }, [etat.nom, etat.modifie])
  const m = etat.modele!
  return (
    <div className="editeur">
      <Ruban ouvrirReglages={ouvrirReglages} />
      <div className="corps-editeur">
        <main className="zone-principale">
          {etat.onglet === 'mcd' && (
            <div className="pile-mcd">
              <OngletsVues />
              <div className="cadre-canevas"><Canevas key={etat.vue ?? 'tout'} /></div>
            </div>
          )}
          {etat.onglet === 'mld' && <VueMLD />}
          {etat.onglet === 'uml' && <VueUML />}
          {etat.onglet === 'sql' && <VueSQL />}
        </main>
        {etat.onglet === 'mcd' && <Inspecteur />}
      </div>
      <footer className="barre-etat">
        <span className="titre-document" title={etat.chemin ?? undefined}>{titre}</span>
        <span className="compte">{m.entities.length} entité{m.entities.length > 1 ? 's' : ''} · {m.associations.length} association{m.associations.length > 1 ? 's' : ''}</span>
        {etat.message && <span className={`message${etat.message.erreur ? ' erreur' : ''}`} role="status">{etat.message.texte}</span>}
        <span className="espace" />
        <button className="lien-texte" onClick={async () => { if (await A.abandonnerModifications()) doc.fermer() }}>Accueil</button>
      </footer>
    </div>
  )
}

export default function App() {
  const etat = useDocument()
  const [pret, setPret] = useState<'chargement' | 'pret' | string>('chargement')
  const [reglages, setReglages] = useState(false)
  const [version, setVersion] = useState('0.1.0')

  useEffect(() => {
    appliquerApparence(lireApparence())
    chargerMoteur()
      .then(async () => {
        setVersion(Moteur.version())
        setPret('pret')
        if (!estBureau) return
        // Fichier ouvert par double-clic dans l'explorateur : on l'ouvre tout de suite.
        const { invoke } = await import('@tauri-apps/api/core')
        const chemin = await invoke<string | null>('fichier_initial')
        if (chemin) A.ouvrirChemin(chemin)
      })
      .catch((e) => setPret(String(e)))
  }, [])

  useEffect(() => {
    const f = (e: KeyboardEvent) => raccourcis(e, () => setReglages(true))
    window.addEventListener('keydown', f)
    // Fermeture de la fenêtre avec des modifications non enregistrées.
    const avant = (e: BeforeUnloadEvent) => { if (doc.etat.modele && doc.etat.modifie) e.preventDefault() }
    let retirer: (() => void) | undefined
    if (estBureau) {
      import('@tauri-apps/api/window').then(async ({ getCurrentWindow }) => {
        const fenetre = getCurrentWindow()
        retirer = await fenetre.onCloseRequested(async (evenement) => {
          if (!(await A.abandonnerModifications())) evenement.preventDefault()
        })
      })
    } else {
      window.addEventListener('beforeunload', avant)
    }
    return () => {
      window.removeEventListener('keydown', f)
      window.removeEventListener('beforeunload', avant)
      retirer?.()
    }
  }, [])

  if (pret === 'chargement') return <div className="chargement" aria-busy="true"><div className="fil" /></div>
  if (pret !== 'pret') {
    return (
      <div className="panne">
        <WarningCircle size={28} weight="fill" />
        <h1>Le moteur de Cardinal n’a pas pu démarrer</h1>
        <p>{pret}</p>
      </div>
    )
  }
  return (
    <>
      {etat.modele ? <Editeur ouvrirReglages={() => setReglages(true)} /> : <Accueil version={version} />}
      {reglages && <Reglages onFermer={() => setReglages(false)} />}
      {!etat.modele && etat.message && <div className={`bulle${etat.message.erreur ? ' erreur' : ''}`} role="status">{etat.message.texte}</div>}
    </>
  )
}
