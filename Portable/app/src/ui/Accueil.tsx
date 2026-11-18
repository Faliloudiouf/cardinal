// Écran d'accueil, comme sur Mac : créer, ouvrir, exemples, fichiers récents.
import { useState } from 'react'
import { FilePlus, FolderOpen, Database, ClockCounterClockwise, X } from '@phosphor-icons/react'
import * as A from '../modele/actions'
import { estBureau, oublierRecent, recents } from '../modele/fichiers'
import { ChoixApparence } from './Reglages'

export function Accueil({ version }: { version: string }) {
  const [liste, setListe] = useState(recents)
  return (
    <main className="accueil">
      <section className="accueil-gauche">
        <div className="marque">
          <img src={`${import.meta.env.BASE_URL}cardinal.png`} alt="" width={84} height={84} />
          <div>
            <h1>Cardinal</h1>
            <p className="version">Version {version} · {estBureau ? 'Windows et Linux' : 'navigateur'}</p>
          </div>
        </div>
        <p className="accroche">Concevez vos bases de données avec Merise : MCD, MLD, UML et script SQL pour six SGBD.</p>
        <nav className="actions-accueil" aria-label="Commencer">
          <button className="action-accueil principale" onClick={A.nouveau}>
            <FilePlus size={22} weight="fill" />
            <span><strong>Nouveau modèle</strong><small>Un MCD vide, prêt à dessiner</small></span>
          </button>
          <button className="action-accueil" onClick={A.ouvrir}>
            <FolderOpen size={22} weight="fill" />
            <span><strong>Ouvrir…</strong><small>Fichier Cardinal (.mcd) ou Looping (.loo)</small></span>
          </button>
          <button className="action-accueil" onClick={A.importerSQL}>
            <Database size={22} weight="fill" />
            <span><strong>Depuis un script SQL…</strong><small>Reconstruit le MCD d’une base existante</small></span>
          </button>
        </nav>
        <div className="exemples">
          <span>Exemples :</span>
          <button className="lien-texte" onClick={() => A.ouvrirExemple('entreprise')}>Gestion d’entreprise</button>
          <button className="lien-texte" onClick={() => A.ouvrirExemple('scolarite')}>Scolarité</button>
        </div>
        <div className="accueil-apparence"><span>Apparence</span><ChoixApparence /></div>
      </section>
      <section className="accueil-droite" aria-labelledby="titre-recents">
        <h2 id="titre-recents"><ClockCounterClockwise size={16} weight="fill" /> Récents</h2>
        {liste.length === 0 ? (
          <p className="aucun-recent">
            {estBureau ? 'Les modèles que vous ouvrirez ou enregistrerez apparaîtront ici.' : 'Les fichiers récents sont disponibles dans la version de bureau.'}
          </p>
        ) : (
          <ul className="recents">
            {liste.map((r) => (
              <li key={r.chemin}>
                <button className="recent" onClick={() => A.ouvrirRecent(r.chemin)} title={r.chemin}>
                  <span className="recent-icone" aria-hidden="true" />
                  <span className="recent-texte">
                    <strong>{r.nom.replace(/\.mcd$/i, '')}</strong>
                    <small>{r.chemin.replace(/[\\/][^\\/]*$/, '')}</small>
                  </span>
                </button>
                <button className="icone-seule retirer" title="Retirer de la liste" onClick={() => { oublierRecent(r.chemin); setListe(recents()) }}>
                  <X size={12} weight="bold" />
                </button>
              </li>
            ))}
          </ul>
        )}
      </section>
    </main>
  )
}
