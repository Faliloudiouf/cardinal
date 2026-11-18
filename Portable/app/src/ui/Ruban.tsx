// Ruban légendé, organisé comme celui de la version Mac (et de Looping) : un groupe par usage.
import {
  ArrowClockwise, ArrowCounterClockwise, CaretDown, Copy, CornersOut, Export, FilePlus, FloppyDisk, FolderOpen,
  GearSix, MagnifyingGlassMinus, MagnifyingGlassPlus, NavigationArrow, Trash, Rows, TextAa, GridFour, ArrowRight,
  Rectangle, Circle, LineSegment, ArrowUpRight, CheckCircle, CopySimple,
} from '@phosphor-icons/react'
import type { ReactNode } from 'react'
import * as A from '../modele/actions'
import { doc, useDocument, type Onglet, type Outil } from '../modele/document'
import { estBureau, recents } from '../modele/fichiers'
import { SGBD, type Reglages, type Sgbd } from '../moteur/types'
import { commandesCanevas, ZOOM_MAX, ZOOM_MIN } from './Canevas'
import { Menu, type ElementMenu } from './Menu'
import { Picto, type NomPicto } from './Pictos'
import { exporterImage } from './exporter'

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
      {children && <span>{children}</span>}
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

function GroupeFichier() {
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

function GroupeFormalisme({ onglet }: { onglet: Onglet }) {
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
  const regler = (z: number) => doc.regler({ zoom: Math.min(ZOOM_MAX, Math.max(ZOOM_MIN, z)) })
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

  return (
    <header className="ruban" role="toolbar" aria-label="Ruban">
      <div className="ruban-groupes">
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
            <Groupe titre="Illustration" className="grille-2">
              <Petit aide="Rectangle" icone={<Rectangle {...IP} />} actif={o === 'rectangle'} onClick={() => doc.regler({ outil: o === 'rectangle' ? 'selection' : 'rectangle' })} />
              <Petit aide="Ellipse" icone={<Circle {...IP} />} actif={o === 'ellipse'} onClick={() => doc.regler({ outil: o === 'ellipse' ? 'selection' : 'ellipse' })} />
              <Petit aide="Trait" icone={<LineSegment {...IP} />} actif={o === 'trait'} onClick={() => doc.regler({ outil: o === 'trait' ? 'selection' : 'trait' })} />
              <Petit aide="Flèche" icone={<ArrowUpRight {...IP} />} actif={o === 'fleche'} onClick={() => doc.regler({ outil: o === 'fleche' ? 'selection' : 'fleche' })} />
            </Groupe>
            <Groupe titre="Édition" className="grille-2">
              <Petit aide={`Annuler (${MOD}Z)`} icone={<ArrowCounterClockwise {...IP} />} desactive={!etat.peutAnnuler} onClick={() => doc.annuler()} />
              <Petit aide={`Rétablir (${MOD}⇧Z)`} icone={<ArrowClockwise {...IP} />} desactive={!etat.peutRetablir} onClick={() => doc.retablir()} />
              <Petit aide={`Dupliquer (${MOD}D)`} icone={<CopySimple {...IP} />} desactive={!etat.selection.length} onClick={A.dupliquer} />
              <Petit aide="Supprimer (Suppr)" icone={<Trash {...IP} />} desactive={!etat.selection.length} onClick={A.supprimerSelection} />
            </Groupe>
            <Groupe titre="Affichage" className="grille-2">
              <Petit aide="Afficher les propriétés des entités" icone={<Rows {...IP} />} actif={s.showAttributes} onClick={() => basculer('showAttributes')} />
              <Petit aide="Afficher les types" icone={<TextAa {...IP} />} actif={s.showTypes} onClick={() => basculer('showTypes')} />
              <Petit aide="Afficher la grille" icone={<GridFour {...IP} />} actif={s.showGrid} onClick={() => basculer('showGrid')} />
              <Petit aide="Flèches de dépendance fonctionnelle (pattes 0,1 et 1,1)" icone={<ArrowRight {...IP} />} actif={s.showDependencies} onClick={() => basculer('showDependencies')} />
            </Groupe>
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
  )
}
