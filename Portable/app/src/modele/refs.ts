import type { Attribut, GenreRef, Modele, Point, Ref } from '../moteur/types'

/** Clé texte d'une référence : « entity:UUID ». Sert pour la sélection et les dictionnaires. */
export function cle(ref: Ref): string {
  const genre = Object.keys(ref)[0] as GenreRef
  return `${genre}:${ref[genre]!._0}`
}

export function ref(genre: GenreRef, id: string): Ref {
  return { [genre]: { _0: id } } as Ref
}

export function depuisCle(c: string): Ref {
  const [genre, id] = c.split(':') as [GenreRef, string]
  return ref(genre, id)
}

export function genreDe(c: string): GenreRef {
  return c.split(':')[0] as GenreRef
}

export function idDe(c: string): string {
  return c.split(':')[1]
}

export function nouvelId(): string {
  return crypto.randomUUID().toUpperCase()
}

export function nouvelAttribut(nom: string, identifiant = false): Attribut {
  return {
    id: nouvelId(), name: nom, type: identifiant ? 'counter' : 'varchar', length: 50, precision: 15, scale: 2,
    isIdentifier: identifiant, isNotNull: false, isUnique: false, label: '', collation: '', complement: '',
    comment: '', enumValues: [], customType: '',
  }
}

/** Liste de tous les éléments positionnés du modèle, avec leur clé. */
export function elements(m: Modele): { cle: string; position: Point }[] {
  return [
    ...m.entities.map((e) => ({ cle: `entity:${e.id}`, position: e.position })),
    ...m.associations.map((a) => ({ cle: `association:${a.id}`, position: a.position })),
    ...m.inheritances.map((h) => ({ cle: `inheritance:${h.id}`, position: h.position })),
    ...m.constraints.map((c) => ({ cle: `constraint:${c.id}`, position: c.position })),
    ...m.rules.map((r) => ({ cle: `rule:${r.id}`, position: r.position })),
    ...m.notes.map((n) => ({ cle: `note:${n.id}`, position: n.position })),
    ...m.figures.map((f) => ({ cle: `figure:${f.id}`, position: f.position })),
  ]
}

export function trouver(m: Modele, c: string): { position: Point } | undefined {
  const id = idDe(c)
  switch (genreDe(c)) {
    case 'entity': return m.entities.find((e) => e.id === id)
    case 'association': return m.associations.find((e) => e.id === id)
    case 'inheritance': return m.inheritances.find((e) => e.id === id)
    case 'constraint': return m.constraints.find((e) => e.id === id)
    case 'rule': return m.rules.find((e) => e.id === id)
    case 'note': return m.notes.find((e) => e.id === id)
    case 'figure': return m.figures.find((e) => e.id === id)
  }
}

export function nomDe(m: Modele, c: string): string {
  const id = idDe(c)
  switch (genreDe(c)) {
    case 'entity': return m.entities.find((e) => e.id === id)?.name || 'Entité sans nom'
    case 'association': return m.associations.find((e) => e.id === id)?.name || 'Association sans nom'
    case 'inheritance': return 'Héritage'
    case 'constraint': return 'Contrainte'
    case 'rule': return m.rules.find((e) => e.id === id)?.name || 'Règle'
    case 'note': return 'Texte'
    case 'figure': return 'Illustration'
  }
}
