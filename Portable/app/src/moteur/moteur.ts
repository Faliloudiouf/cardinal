// Accès au moteur de Cardinal (Swift compilé en WebAssembly). Appels synchrones :
// une requête JSON entre, une réponse JSON sort. Le dessin d'un MCD prend environ 3 ms.
import { WASI, OpenFile, File, ConsoleStdout } from '@bjorn3/browser_wasi_shim'
import type {
  AnalyseAttribut, Attribut, Dessin, Diagnostic, MLD, Modele, Ref, Sgbd, TypeInfo, UML,
} from './types'

interface Exports {
  memory: WebAssembly.Memory
  cardinal_alloc(taille: number): number
  cardinal_free(pointeur: number): void
  cardinal_call(pointeur: number, taille: number): number
  cardinal_result(): number
  _initialize(): void
}

let moteur: Exports | null = null
const encodeur = new TextEncoder()
const decodeur = new TextDecoder()

export async function chargerMoteur(): Promise<void> {
  if (moteur) return
  const wasi = new WASI([], [], [
    new OpenFile(new File([])),
    ConsoleStdout.lineBuffered((ligne) => console.log('[moteur]', ligne)),
    ConsoleStdout.lineBuffered((ligne) => console.warn('[moteur]', ligne)),
  ])
  const url = `${import.meta.env.BASE_URL}cardinal.wasm`
  const imports = { wasi_snapshot_preview1: wasi.wasiImport }
  let instance: WebAssembly.Instance
  try {
    instance = (await WebAssembly.instantiateStreaming(fetch(url), imports)).instance
  } catch {
    // Certains serveurs ne donnent pas le bon type MIME : on retombe sur la lecture complète.
    const octets = await (await fetch(url)).arrayBuffer()
    instance = (await WebAssembly.instantiate(octets, imports)).instance
  }
  wasi.initialize(instance as unknown as { exports: { memory: WebAssembly.Memory; _initialize?: () => unknown } })
  moteur = instance.exports as unknown as Exports
}

export class ErreurMoteur extends Error {}

function appeler<T>(requete: object): T {
  if (!moteur) throw new ErreurMoteur('Le moteur n’est pas encore chargé.')
  const octets = encodeur.encode(JSON.stringify(requete))
  const pointeur = moteur.cardinal_alloc(octets.length)
  new Uint8Array(moteur.memory.buffer, pointeur, octets.length).set(octets)
  const taille = moteur.cardinal_call(pointeur, octets.length)
  moteur.cardinal_free(pointeur)
  const texte = decodeur.decode(new Uint8Array(moteur.memory.buffer, moteur.cardinal_result(), taille))
  const reponse = JSON.parse(texte) as { ok?: T; erreur?: string }
  if (reponse.erreur !== undefined) throw new ErreurMoteur(reponse.erreur)
  return reponse.ok as T
}

function base64(octets: Uint8Array): string {
  let binaire = ''
  for (let i = 0; i < octets.length; i += 0x8000) binaire += String.fromCharCode(...octets.subarray(i, i + 0x8000))
  return btoa(binaire)
}

export const Moteur = {
  version: () => appeler<string>({ op: 'version' }),
  vide: () => appeler<Modele>({ op: 'vide' }),
  exemple: (nom: 'entreprise' | 'scolarite') => appeler<Modele>({ op: 'exemple', nom }),
  lire: (octets: Uint8Array, looping: boolean) => appeler<Modele>({ op: 'lire', base64: base64(octets), looping }),
  encoder: (modele: Modele) => appeler<string>({ op: 'encoder', modele }),
  dessin: (modele: Modele, vue?: string | null) => appeler<Dessin>({ op: 'dessin', modele, vue: vue ?? undefined }),
  verifier: (modele: Modele) => appeler<Diagnostic[]>({ op: 'verifier', modele }),
  mld: (modele: Modele) => appeler<MLD>({ op: 'mld', modele }),
  uml: (modele: Modele, simplifie: boolean) => appeler<UML>({ op: 'uml', modele, simplifie }),
  sql: (modele: Modele, sgbd: Sgbd) => appeler<string>({ op: 'sql', modele, sgbd }),
  xml: (modele: Modele) => appeler<string>({ op: 'xml', modele }),
  retro: (sql: string) => appeler<Modele>({ op: 'retro', sql }),
  types: () => appeler<TypeInfo[]>({ op: 'types' }),
  attribut: (attribut: Attribut, type?: string, normaliser = false) =>
    appeler<AnalyseAttribut>({ op: 'attribut', attribut, type, normaliser }),
  modifier: (modele: Modele, action: string, extra: Record<string, unknown> = {}) =>
    appeler<{ modele: Modele; refs: Ref[] }>({ op: 'modifier', modele, action, ...extra }),
  nomLibre: (modele: Modele, base: string) => appeler<{ nom: string }>({ op: 'modifier', modele, action: 'nom', base }).nom,
}
