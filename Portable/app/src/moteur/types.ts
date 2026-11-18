// Types du modèle, identiques au format .mcd (JSON) de Cardinal sur Mac.
// Les positions sont des tableaux [x, y], comme dans les fichiers écrits par la version Mac.

export type Point = [number, number]
export type Taille = [number, number]

export type GenreRef = 'entity' | 'association' | 'inheritance' | 'constraint' | 'rule' | 'note' | 'figure'
export type Ref = { [K in GenreRef]?: { _0: string } }

export type Couleur = 'auto' | 'bleu' | 'sarcelle' | 'vert' | 'violet' | 'rouge' | 'ardoise'
export type Cardinalite = '0,1' | '1,1' | '0,N' | '1,N'

export interface Attribut {
  id: string
  name: string
  type: string
  length: number
  precision: number
  scale: number
  isIdentifier: boolean
  isNotNull: boolean
  isUnique: boolean
  label: string
  collation: string
  complement: string
  comment: string
  enumValues: string[]
  customType: string
}

export interface Entite {
  id: string
  name: string
  attributes: Attribut[]
  position: Point
  isFictive: boolean
  color: Couleur
}

export interface Patte {
  id: string
  entityID: string
  cardinality: Cardinalite
  isRelative: boolean
  role: string
  bend?: Point | null
}

export interface Association {
  id: string
  name: string
  attributes: Attribut[]
  legs: Patte[]
  position: Point
  color: Couleur
}

export interface Heritage {
  id: string
  parentID?: string | null
  childIDs: string[]
  kind: '' | 'X' | 'T' | 'XT'
  strategy: 'tablesSousTypes' | 'sousTypesSeuls' | 'surtypeSeul'
  position: Point
}

export interface LienContrainte { id: string; target: Ref; isTarget: boolean }
export interface Contrainte {
  id: string
  kind: 'CIF' | 'I' | 'X' | 'T' | 'XT' | 'S' | '='
  links: LienContrainte[]
  position: Point
  sql: string
}

export interface Regle { id: string; name: string; details: string; sql: string; links: Ref[]; position: Point }
export interface Note { id: string; text: string; style: 'titre' | 'texte'; position: Point }
export interface Figure {
  id: string
  kind: 'rectangle' | 'ellipse' | 'line' | 'arrow' | 'image'
  position: Point
  size: Taille
  span: Point
  color: Couleur
  isFilled: boolean
  imageData?: string | null
}
export interface Vue { id: string; name: string; refs: Ref[] }

export interface Reglages {
  naming: 'telQuel' | 'snake' | 'camel' | 'pascal' | 'majuscules'
  foreignKeysAtEnd: boolean
  showTypes: boolean
  showAttributes: boolean
  showGrid: boolean
  useLabels: boolean
  showDependencies: boolean
}

export interface Modele {
  version: number
  entities: Entite[]
  associations: Association[]
  inheritances: Heritage[]
  constraints: Contrainte[]
  rules: Regle[]
  notes: Note[]
  figures: Figure[]
  views: Vue[]
  settings: Reglages
}

// Réponses du moteur

export interface Rect { x: number; y: number; w: number; h: number }
export interface P { x: number; y: number }

export interface Dessin {
  noeuds: { ref: Ref; cadre: Rect }[]
  pattes: { association: string; patte: number; points: P[]; maxUn: boolean }[]
  etiquettes: { texte: string; association: string; patte: number; ancre: P; cadre: Rect }[]
  ports: Record<string, P>
  types: { id: string; type: string }[]
  limites: Rect | null
}

export interface Diagnostic { gravite: 'erreur' | 'avertissement'; message: string; cible?: Ref | null }

export interface MLD {
  tables: {
    nom: string
    colonnes: { nom: string; type: string; cle: boolean; nulle: boolean; unique: boolean; reference?: string | null }[]
    association: boolean
    origine?: Ref | null
    centre: P
    taille: P
  }[]
  liens: { enfant: string; parent: string; points: P[]; colonnes: string[] }[]
  taille: P
}

export interface UML {
  classes: { id: string; nom: string; lignes: { texte: string; identifiant: boolean }[]; cadre: Rect; classeAssociation: boolean }[]
  traits: { points: P[]; style: 'plein' | 'pointille' | 'generalisation' }[]
  etiquettes: { texte: string; genre: 'multiplicite' | 'role' | 'nom'; cadre: Rect }[]
  losanges: { centre: P }[]
  taille: P
}

export interface TypeInfo {
  id: string
  categorie: 'texte' | 'numerique' | 'dateHeure' | 'autre'
  categorieLibelle: string
  libelle: string
  menu: string
  aide: string
  encodage?: 'ascii' | 'unicode' | 'binaire' | null
  stockage?: 'variable' | 'fixe' | 'volumineux' | null
  longueur: boolean
  precision: boolean
  collation: boolean
  longueurMax: number
}

export interface AnalyseAttribut {
  attribut: Attribut
  affichage: string
  apercu: Record<string, string>
  problemes: { texte: string; erreur: boolean }[]
}

export const SGBD = ['MySQL', 'MariaDB', 'PostgreSQL', 'SQLite', 'SQL Server', 'Oracle'] as const
export type Sgbd = (typeof SGBD)[number]
