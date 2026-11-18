// Ruban légendé, organisé comme celui de la version Mac (et de Looping) : un groupe par usage.
import {
  ArrowClockwise, ArrowCounterClockwise, CaretDown, Copy, CornersOut, Export, FilePlus, FloppyDisk, FolderOpen,
  GearSix, MagnifyingGlassMinus, MagnifyingGlassPlus, NavigationArrow, Trash, Rows, TextAa, GridFour, ArrowRight,
  Rectangle, Circle, LineSegment, ArrowUpRight, CheckCircle, CopySimple,
} from '@phosphor-icons/react'
import { createContext, useContext, useLayoutEffect, useRef, useState, type ReactNode } from 'react'
import * as A from '../modele/actions'
import { doc, useDocument, type Onglet, type Outil } from '../modele/document'
import { estBureau, recents } from '../modele/fichiers'
import { SGBD, type Reglages, type Sgbd } from '../moteur/types'
import { commandesCanevas, ZOOM_MAX, ZOOM_MIN } from './Canevas'
import { Menu, type ElementMenu } from './Menu'
import { Picto, type NomPicto } from './Pictos'
import { exporterImage } from './exporter'

/** Densité du ruban : étalé, resserré (petits groupes en boutons-menus), replié. Les noms restent visibles. */
type Densite = 'large' | 'moyen' | 'petit'
const ContexteDensite = createContext<Densite>('large')
const ORDRE: Densite[] = ['large', 'moyen', 'petit']

export const MOD = typeof navigator !== 'undefined' && /Mac/.test(navigator.platform) ? '⌘' : 'Ctrl+'

function Groupe({ titre, children, className }: { titre: string; children: ReactNode; className?: string }) {
  return (
    <section className={`groupe ${className ?? ''}`} aria-label={titre}>
      <div className="groupe-contenu">{children}</div>
      <h3 className="groupe-titre">{titre}</h3>
    </section>
  )
}

function Bouton({ titre, aide, icone, actif, desactive, onClick }: {
  titre: string; aide: string; icone: ReactNode; actif?: boolean; desactive?: boolean; onClick: () => void
}) {
  return (
    <button className="bouton-ruban" title={aide} aria-pressed={actif} disabled={desactive} onClick={onClick}>
      <span className="icone-ruban">{icone}</span>
      <span className="libelle-ruban">{titre}</span>
    </button>
  )
}

function Petit({ aide, icone, actif, desactive, onClick, children }: {
  aide: string; icone: ReactNode; actif?: boolean; desactive?: boolean; onClick: () => void; children?: ReactNode
}) {
  return (
    <button className="petit-ruban" title={aide} aria-pressed={actif} disabled={desactive} onClick={onClick}>
      {icone}
      {children && <span className="petit-libelle">{children}</span>}
    </button>
  )
}

const I = { size: 22, weight: 'fill' as const }
const IP = { size: 16, weight: 'fill' as const }

function BoutonDouble({ titre, aide, icone, onClick, menu }: {
  titre: string; aide: string; icone: ReactNode; onClick: () => void; menu: () => ElementMenu[]
}) {
  return (
    <div className="bouton-double">
      <button className="bouton-ruban" title={aide} onClick={onClick}>
        <span className="icone-ruban">{icone}</span>
        <span className="libelle-ruban">{titre}</span>
      </button>
      <Menu elements={menu} className="fleche-double" titre={`Plus d’options : ${titre}`}>
        <CaretDown size={10} weight="bold" />
      </Menu>
    </div>
  )
}

/** Groupe replié en un bouton : icône, nom et flèche ; ouvre un menu. */
function BoutonMenu({ titre, aide, icone, elements }: { titre: string; aide: string; icone: ReactNode; elements: () => ElementMenu[] }) {
  return (
    <Menu elements={elements} className="bouton-menu-ruban" titre={aide}>
      <span className="icone-ruban">{icone}</span>
      <span className="libelle-ruban">{titre} ▾</span>
    </Menu>
  )
}

function GroupeFichier() {
  const densite = useContext(ContexteDensite)
  if (densite === 'petit') {
    return (
      <Groupe titre="Fichier">
        <BoutonMenu titre="Fichier" aide="Nouveau, ouvrir, enregistrer, exporter" icone={<FilePlus {...I} />} elements={() => [
          { libelle: 'Nouveau modèle', action: A.nouveau, raccourci: `${MOD}N` },
          { libelle: 'Exemple : gestion d’entreprise', action: () => A.ouvrirExemple('entreprise') },
          { libelle: 'Exemple : scolarité', action: () => A.ouvrirExemple('scolarite') },
          { separateur: true, libelle: '' },
          { libelle: 'Ouvrir…', action: A.ouvrir, raccourci: `${MOD}O` },
          ...recents().slice(0, 6).map((r) => ({ libelle: `Récent : ${r.nom}`, action: () => A.ouvrirRecent(r.chemin) })),
          { separateur: true, libelle: '' },
          { libelle: 'Enregistrer', action: () => A.enregistrer(), raccourci: `${MOD}S` },
          { libelle: 'Enregistrer sous…', action: () => A.enregistrer(true), raccourci: `${MOD}⇧S` },
          { separateur: true, libelle: '' },
          { libelle: 'Image PNG du diagramme…', action: () => exporterImage('png'), desactive: doc.etat.onglet === 'sql' },
          { libelle: 'Script SQL…', action: A.exporterSQL },
          { libelle: 'Rétroconception d’un script SQL…', action: A.importerSQL },
        ]} />
      </Groupe>
    )
  }
  return <GroupeFichierComplet />
}

function GroupeFichierComplet() {
  return (
    <Groupe titre="Fichier" className="groupe-fichier">
      <BoutonDouble
        titre="Nouveau" aide={`Nouveau modèle vide (${MOD}N) ; la flèche propose les exemples et les imports`}
        icone={<FilePlus {...I} />} onClick={A.nouveau}
        menu={() => [
          { libelle: 'Modèle vide', action: A.nouveau, raccourci: `${MOD}N` },
          { separateur: true, libelle: '' },
          { titre: true, libelle: 'Exemples' },
          { libelle: 'Gestion d’entreprise', action: () => A.ouvrirExemple('entreprise') },
          { libelle: 'Scolarité', action: () => A.ouvrirExemple('scolarite') },
          { separateur: true, libelle: '' },
          { libelle: 'Rétroconception d’un script SQL…', action: A.importerSQL },
        ]}
      />
      <BoutonDouble
        titre="Ouvrir" aide={`Ouvrir un modèle .mcd ou un fichier Looping .loo (${MOD}O)`}
        icone={<FolderOpen {...I} />} onClick={A.ouvrir}
        menu={() => {
          const liste = recents()
          return [
            { libelle: 'Ouvrir…', action: A.ouvrir, raccourci: `${MOD}O` },
            { separateur: true, libelle: '' },
            { titre: true, libelle: estBureau ? 'Récents' : 'Récents (version de bureau)' },
            ...(liste.length ? liste.map((r) => ({ libelle: r.nom, action: () => A.ouvrirRecent(r.chemin) })) : [{ libelle: 'Aucun fichier récent', desactive: true }]),
          ]
        }}
      />
      <BoutonDouble
        titre="Enregistrer" aide={`Enregistrer le modèle (${MOD}S)`} icone={<FloppyDisk {...I} />} onClick={() => A.enregistrer()}
        menu={() => [
          { libelle: 'Enregistrer', action: () => A.enregistrer(), raccourci: `${MOD}S` },
          { libelle: 'Enregistrer sous…', action: () => A.enregistrer(true), raccourci: `${MOD}⇧S` },
          { separateur: true, libelle: '' },
          { titre: true, libelle: 'Exporter' },
          { libelle: 'Image PNG du diagramme…', action: () => exporterImage('png'), desactive: doc.etat.onglet === 'sql' },
          { libelle: 'Image SVG du diagramme…', action: () => exporterImage('svg'), desactive: doc.etat.onglet === 'sql' },
          { libelle: 'Script SQL…', action: A.exporterSQL },
        ]}
      />
    </Groupe>
  )
}

const FORMALISMES: { o: Onglet; titre: string; picto: NomPicto; aide: string }[] = [
  { o: 'mcd', titre: 'E/A', picto: 'mcd', aide: 'Modèle Entité/Association' },
  { o: 'mld', titre: 'MLD', picto: 'mld', aide: 'Modèle logique de données' },
  { o: 'uml', titre: 'UML', picto: 'uml', aide: 'Diagramme de classes UML' },
  { o: 'sql', titre: 'SQL', picto: 'sql', aide: 'Script SQL de création des tables' },
]

function GroupeFormalisme({ onglet }: { onglet: Onglet }) {
  const densite = useContext(ContexteDensite)
  if (densite === 'petit') {
    const actuel = FORMALISMES.find((f) => f.o === onglet)!
    return (
      <Groupe titre="Formalisme">
        <BoutonMenu titre={actuel.titre} aide="Changer de formalisme" icone={<Picto nom={actuel.picto} />}
          elements={() => FORMALISMES.map((f, i) => ({ libelle: `${f.titre} : ${f.aide}`, coche: f.o === onglet, raccourci: `${MOD}${i + 1}`, action: () => doc.regler({ onglet: f.o }) }))} />
      </Groupe>
    )
  }
  return <GroupeFormalismeComplet onglet={onglet} />
}

function GroupeFormalismeComplet({ onglet }: { onglet: Onglet }) {
  const f = (o: Onglet, titre: string, picto: NomPicto, aide: string, n: number) => (
    <Bouton titre={titre} aide={`${aide} (${MOD}${n})`} icone={<Picto nom={picto} />} actif={onglet === o} onClick={() => doc.regler({ onglet: o })} />
  )
  return (
    <Groupe titre="Formalisme" className="groupe-formalisme">
      {f('mcd', 'E/A', 'mcd', 'Modèle Entité/Association', 1)}
      {f('mld', 'MLD', 'mld', 'Modèle logique de données', 2)}
      {f('uml', 'UML', 'uml', 'Diagramme de classes UML', 3)}
      {f('sql', 'SQL', 'sql', 'Script SQL de création des tables', 4)}
    </Groupe>
  )
}

function Zoom() {
  const { zoom } = useDocument()
  const densite = useContext(ContexteDensite)
  const regler = (z: number) => doc.regler({ zoom: Math.min(ZOOM_MAX, Math.max(ZOOM_MIN, z)) })
  if (densite !== 'large') {
    return (
      <Groupe titre="Zoom">
        <BoutonMenu titre={`${Math.round(zoom * 100)} %`} aide="Zoom" icone={<MagnifyingGlassPlus {...I} />} elements={() => [
          { libelle: 'Zoom avant', action: () => regler(zoom * 1.2), raccourci: `${MOD}+` },
          { libelle: 'Zoom arrière', action: () => regler(zoom / 1.2), raccourci: `${MOD}−` },
          { separateur: true, libelle: '' },
          ...[0.5, 0.75, 1, 1.5, 2].map((z) => ({ libelle: `${z * 100} %`, coche: Math.abs(zoom - z) < 0.01, action: () => regler(z) })),
          { separateur: true, libelle: '' },
          { libelle: 'Ajuster à la fenêtre', action: () => commandesCanevas.ajuster(), raccourci: `${MOD}9` },
        ]} />
      </Groupe>
    )
  }
  return (
    <Groupe titre="Zoom" className="groupe-zoom">
      <div className="zoom">
        <Petit aide={`Zoom arrière (${MOD}−)`} icone={<MagnifyingGlassMinus {...IP} />} onClick={() => regler(zoom / 1.2)} />
        <button className="valeur-zoom" title="Revenir à 100 %" onClick={() => regler(1)}>{Math.round(zoom * 100)} %</button>
        <Petit aide={`Zoom avant (${MOD}+)`} icone={<MagnifyingGlassPlus {...IP} />} onClick={() => regler(zoom * 1.2)} />
      </div>
      <Bouton titre="Ajuster" aide={`Ajuster à la fenêtre (${MOD}9)`} icone={<CornersOut {...I} />} onClick={() => commandesCanevas.ajuster()} />
    </Groupe>
  )
}

function OutilMCD({ outil, nom, titre, picto, aide }: { outil: Outil; nom: Outil; titre: string; picto: NomPicto; aide: string }) {
  return (
    <Bouton
      titre={titre} aide={aide} icone={<Picto nom={picto} />} actif={outil === nom}
      onClick={() => doc.regler({ outil: outil === nom ? 'selection' : nom, attente: null })}
    />
  )
}

function basculer(cle: keyof Reglages) {
  doc.modifier((m) => {
    ;(m.settings[cle] as boolean) = !m.settings[cle]
  })
}

export function Ruban({ ouvrirReglages }: { ouvrirReglages: () => void }) {
  const etat = useDocument()
  const m = etat.modele!
  const o = etat.outil
  const s = m.settings
  const groupes = useRef<HTMLDivElement>(null)
  const [densite, setDensite] = useState<Densite>('large')
  // Compteur de mesures : même si la densité est déjà « large », un redimensionnement doit refaire la mesure.
  const [, setMesure] = useState(0)
  const remesurer = () => { setDensite('large'); setMesure((n) => n + 1) }

  // Comme le ruban de la version Mac : on essaie la densité la plus aérée qui tient, sans jamais
  // cacher le nom d'un bouton. Agrandir la fenêtre fait repartir de « large ».
  useLayoutEffect(() => {
    const el = groupes.current
    if (el && el.scrollWidth > el.clientWidth + 1) {
      const i = ORDRE.indexOf(densite)
      if (i < ORDRE.length - 1) setDensite(ORDRE[i + 1])
    }
  })
  useLayoutEffect(() => {
    const el = groupes.current
    if (!el) return
    // À chaque changement de largeur, on repart de « large » : les effets ci-dessus resserrent
    // aussitôt, avant l'affichage (pas de clignotement).
    let largeur = el.clientWidth
    const observateur = new ResizeObserver(() => {
      if (Math.abs(el.clientWidth - largeur) > 2) remesurer()
      largeur = el.clientWidth
    })
    observateur.observe(el)
    // La fenêtre elle-même (l'observateur dépend du rendu, suspendu quand la fenêtre est cachée).
    const fenetre = () => remesurer()
    window.addEventListener('resize', fenetre)
    return () => {
      observateur.disconnect()
      window.removeEventListener('resize', fenetre)
    }
  }, [])
  useLayoutEffect(() => setDensite('large'), [etat.onglet])

  const formes: { outil: Outil; titre: string; icone: ReactNode }[] = [
    { outil: 'rectangle', titre: 'Rectangle', icone: <Rectangle {...IP} /> },
    { outil: 'ellipse', titre: 'Ellipse', icone: <Circle {...IP} /> },
    { outil: 'trait', titre: 'Trait', icone: <LineSegment {...IP} /> },
    { outil: 'fleche', titre: 'Flèche', icone: <ArrowUpRight {...IP} /> },
  ]
  const choisir = (x: Outil) => doc.regler({ outil: o === x ? 'selection' : x, attente: null })

  return (
    <ContexteDensite.Provider value={densite}>
    <header className={`ruban densite-${densite}`} role="toolbar" aria-label="Ruban">
      <div className="ruban-groupes" ref={groupes}>
        <GroupeFichier />
        <GroupeFormalisme onglet={etat.onglet} />

        {etat.onglet === 'mcd' && (
          <>
            <Groupe titre="Pointeur" className="groupe-pointeur">
              <Bouton titre="Sélection" aide="Sélectionner et déplacer (Échap)" icone={<NavigationArrow {...I} style={{ transform: 'scaleX(-1)' }} />}
                actif={o === 'selection'} onClick={() => doc.regler({ outil: 'selection', attente: null })} />
            </Groupe>
            <Groupe titre="MCD" className="groupe-outils">
              <OutilMCD outil={o} nom="entite" titre="Entité" picto="entite" aide="Entité : cliquez sur le canevas pour la poser (E)" />
              <OutilMCD outil={o} nom="association" titre="Association" picto="association" aide="Association : cliquez sur le canevas pour la poser (A)" />
              <OutilMCD outil={o} nom="lien" titre="Lien" picto="patte" aide="Lien : cliquez sur une entité puis sur une association (L)" />
              <OutilMCD outil={o} nom="heritage" titre="Héritage" picto="heritage" aide="Héritage : posez-le puis reliez le surtype et les sous-types" />
              <OutilMCD outil={o} nom="contrainte" titre="Contrainte" picto="contrainte" aide="Contrainte entre associations (X, T, XT, I, S, =)" />
              <OutilMCD outil={o} nom="cif" titre="CIF" picto="cif" aide="Contrainte d’intégrité fonctionnelle" />
              <OutilMCD outil={o} nom="regle" titre="Règle" picto="regle" aide="Règle de gestion, avec son code SQL" />
              <OutilMCD outil={o} nom="note" titre="Texte" picto="texte" aide="Texte libre ou titre" />
            </Groupe>
            {densite === 'large' ? (
              <>
                <Groupe titre="Illustration" className="grille-2">
                  {formes.map((f) => <Petit key={f.outil} aide={f.titre} icone={f.icone} actif={o === f.outil} onClick={() => choisir(f.outil)}>{f.titre}</Petit>)}
                </Groupe>
                <Groupe titre="Édition" className="grille-2">
                  <Petit aide={`Annuler (${MOD}Z)`} icone={<ArrowCounterClockwise {...IP} />} desactive={!etat.peutAnnuler} onClick={() => doc.annuler()}>Annuler</Petit>
                  <Petit aide={`Rétablir (${MOD}⇧Z)`} icone={<ArrowClockwise {...IP} />} desactive={!etat.peutRetablir} onClick={() => doc.retablir()}>Rétablir</Petit>
                  <Petit aide={`Dupliquer (${MOD}D)`} icone={<CopySimple {...IP} />} desactive={!etat.selection.length} onClick={A.dupliquer}>Dupliquer</Petit>
                  <Petit aide="Supprimer (Suppr)" icone={<Trash {...IP} />} desactive={!etat.selection.length} onClick={A.supprimerSelection}>Supprimer</Petit>
                </Groupe>
                <Groupe titre="Affichage" className="grille-2">
                  <Petit aide="Afficher les propriétés des entités" icone={<Rows {...IP} />} actif={s.showAttributes} onClick={() => basculer('showAttributes')}>Propriétés</Petit>
                  <Petit aide="Afficher les types" icone={<TextAa {...IP} />} actif={s.showTypes} onClick={() => basculer('showTypes')}>Types</Petit>
                  <Petit aide="Afficher la grille" icone={<GridFour {...IP} />} actif={s.showGrid} onClick={() => basculer('showGrid')}>Grille</Petit>
                  <Petit aide="Flèches de dépendance fonctionnelle (pattes 0,1 et 1,1)" icone={<ArrowRight {...IP} />} actif={s.showDependencies} onClick={() => basculer('showDependencies')}>Dépendances</Petit>
                </Groupe>
              </>
            ) : (
              <>
                <Groupe titre="Illustration">
                  <BoutonMenu titre="Formes" aide="Rectangle, ellipse, trait, flèche" icone={<Rectangle {...I} />}
                    elements={() => formes.map((f) => ({ libelle: f.titre, coche: o === f.outil, action: () => choisir(f.outil) }))} />
                </Groupe>
                <Groupe titre="Édition">
                  <BoutonMenu titre="Édition" aide="Annuler, rétablir, dupliquer, supprimer" icone={<ArrowCounterClockwise {...I} />} elements={() => [
                    { libelle: 'Annuler', action: () => doc.annuler(), desactive: !doc.etat.peutAnnuler, raccourci: `${MOD}Z` },
                    { libelle: 'Rétablir', action: () => doc.retablir(), desactive: !doc.etat.peutRetablir, raccourci: `${MOD}⇧Z` },
                    { separateur: true, libelle: '' },
                    { libelle: 'Dupliquer', action: A.dupliquer, desactive: !doc.etat.selection.length, raccourci: `${MOD}D` },
                    { libelle: 'Supprimer', action: A.supprimerSelection, desactive: !doc.etat.selection.length, raccourci: 'Suppr' },
                  ]} />
                </Groupe>
                <Groupe titre="Affichage">
                  <BoutonMenu titre="Afficher" aide="Propriétés, types, grille, dépendances" icone={<Rows {...I} />} elements={() => [
                    { libelle: 'Propriétés', coche: s.showAttributes, action: () => basculer('showAttributes') },
                    { libelle: 'Types', coche: s.showTypes, action: () => basculer('showTypes') },
                    { libelle: 'Grille', coche: s.showGrid, action: () => basculer('showGrid') },
                    { libelle: 'Dépendances fonctionnelles', coche: s.showDependencies, action: () => basculer('showDependencies') },
                  ]} />
                </Groupe>
              </>
            )}
            <Zoom />
          </>
        )}

        {etat.onglet === 'mld' && (
          <>
            <Groupe titre="Exporter">
              <Bouton titre="XML" aide="Exporter le MLD au format XML" icone={<Export {...I} />} onClick={A.exporterXML} />
            </Groupe>
            <Zoom />
          </>
        )}

        {etat.onglet === 'uml' && (
          <>
            <Groupe titre="Présentation UML">
              <Bouton titre="Standard" aide="Classes avec leurs attributs" icone={<Picto nom="uml" />} actif={!etat.umlSimplifie} onClick={() => doc.regler({ umlSimplifie: false })} />
              <Bouton titre="Simplifié" aide="Classes réduites à leur nom" icone={<Picto nom="umlSimple" />} actif={etat.umlSimplifie} onClick={() => doc.regler({ umlSimplifie: true })} />
            </Groupe>
            <Zoom />
          </>
        )}

        {etat.onglet === 'sql' && (
          <>
            <Groupe titre="SGBD cible">
              <select className="champ choix-sgbd" value={etat.sgbd} aria-label="SGBD cible" onChange={(e) => doc.regler({ sgbd: e.target.value as Sgbd })}>
                {SGBD.map((x) => <option key={x}>{x}</option>)}
              </select>
            </Groupe>
            <Groupe titre="Script">
              <Bouton titre={etat.copie ? 'Copié' : 'Copier'} aide={`Copier le script (${MOD}⇧C)`} icone={etat.copie ? <CheckCircle {...I} /> : <Copy {...I} />} onClick={A.copierSQL} />
              <Bouton titre="Exporter" aide="Enregistrer le script .sql" icone={<Export {...I} />} onClick={A.exporterSQL} />
            </Groupe>
          </>
        )}
      </div>
      <div className="ruban-fin">
        <Bouton titre="Réglages" aide={`Réglages de Cardinal (${MOD},)`} icone={<GearSix {...I} />} onClick={ouvrirReglages} />
      </div>
    </header>
    </ContexteDensite.Provider>
  )
}
