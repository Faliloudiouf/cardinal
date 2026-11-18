// Miniatures du ruban : chaque outil montre la forme qu'il crée sur le canevas, dans les couleurs
// de Cardinal (mêmes dessins que la version Mac). Aucune bibliothèque d'icônes ne propose de
// symboles Merise : ces dessins sont originaux, cadre 30 × 24, traits de 1,2 à 1,4.

export type NomPicto =
  | 'entite' | 'association' | 'heritage' | 'contrainte' | 'cif' | 'regle' | 'patte' | 'texte'
  | 'mcd' | 'mld' | 'uml' | 'sql' | 'umlSimple'

const papier = 'var(--papier)'

export function Picto({ nom }: { nom: NomPicto }) {
  return (
    <svg width="30" height="24" viewBox="0 0 30 24" aria-hidden="true" className="picto">
      {dessin(nom)}
    </svg>
  )
}

function dessin(nom: NomPicto) {
  switch (nom) {
    case 'entite':
      return (
        <g>
          <clipPath id="pe"><rect x="3.6" y="2.1" width="22.8" height="19.8" rx="3" /></clipPath>
          <rect x="3.6" y="2.1" width="22.8" height="19.8" rx="3" fill={papier} />
          <rect x="3" y="1.5" width="24" height="7" fill="var(--entite-fond)" clipPath="url(#pe)" />
          <rect x="7" y="11" width="12" height="1.6" rx="0.8" fill="var(--entite)" />
          <rect x="7" y="14.6" width="15" height="1.6" rx="0.8" fill="var(--encre-3)" />
          <rect x="7" y="18.2" width="10" height="1.6" rx="0.8" fill="var(--encre-3)" />
          <rect x="3.6" y="2.1" width="22.8" height="19.8" rx="3" fill="none" stroke="var(--entite)" strokeWidth="1.2" />
        </g>
      )
    case 'association':
      return (
        <g>
          <rect x="1.7" y="5.2" width="26.6" height="13.6" rx="6.8" fill={papier} />
          <rect x="1.7" y="5.2" width="26.6" height="13.6" rx="6.8" fill="var(--association)" fillOpacity="0.16" stroke="var(--association)" strokeWidth="1.4" />
          <rect x="8.5" y="11.1" width="13" height="1.8" rx="0.9" fill="var(--association)" />
        </g>
      )
    case 'heritage':
      return (
        <g>
          <rect x="9" y="0.5" width="12" height="6" rx="1.5" fill="var(--entite-fond)" />
          <path d="M15 6.5V8M12 15L7 17.5M18 15L23 17.5" stroke="var(--entite)" strokeWidth="1.1" fill="none" />
          <path d="M15 8L21 15H9Z" fill={papier} stroke="var(--entite)" strokeWidth="1.3" strokeLinejoin="round" />
          <rect x="2" y="17.5" width="10" height="6" rx="1.5" fill="var(--entite-fond)" />
          <rect x="18" y="17.5" width="10" height="6" rx="1.5" fill="var(--entite-fond)" />
        </g>
      )
    case 'contrainte':
    case 'cif': {
      const plein = nom === 'cif'
      const teinte = plein ? 'var(--cif)' : 'var(--contrainte)'
      return (
        <g>
          <circle cx="15" cy="12" r="9.8" fill={plein ? teinte : papier} />
          {!plein && <circle cx="15" cy="12" r="9.8" fill={teinte} fillOpacity="0.14" />}
          <circle cx="15" cy="12" r="9.8" fill="none" stroke={teinte} strokeWidth="1.4" />
          <text x="15" y={plein ? 14.5 : 15.6} textAnchor="middle" fontSize={plein ? 7 : 10} fontWeight="800" fill={plein ? '#fff' : teinte}>
            {plein ? 'CIF' : 'X'}
          </text>
        </g>
      )
    }
    case 'regle':
      return (
        <g>
          <path d="M6 1H18L24 7V23H6Z" fill={papier} />
          <path d="M6 1H18L24 7V23H6Z" fill="var(--regle)" fillOpacity="0.14" stroke="var(--regle)" strokeWidth="1.3" strokeLinejoin="round" />
          <path d="M18 1V7H24" fill="none" stroke="var(--regle)" strokeWidth="1" />
          <text x="14" y="17.5" textAnchor="middle" fontSize="10" fontWeight="800" fill="var(--regle)">R</text>
        </g>
      )
    case 'patte':
      return (
        <g>
          <rect x="1" y="11.3" width="28" height="1.4" fill="var(--encre)" fillOpacity="0.75" />
          <rect x="7.5" y="7.2" width="15" height="9.6" rx="4.8" fill={papier} stroke="var(--association)" strokeOpacity="0.7" strokeWidth="0.8" />
          <text x="15" y="14.6" textAnchor="middle" fontSize="7.5" fontWeight="800" fill="var(--association)">0,N</text>
        </g>
      )
    case 'texte':
      return (
        <g>
          <text x="15" y="17" textAnchor="middle" fontSize="18" fontWeight="700" fontFamily="Georgia, 'Times New Roman', serif" fill="var(--encre)">T</text>
          <rect x="7" y="20" width="16" height="1.4" rx="0.7" fill="var(--encre-3)" />
        </g>
      )
    case 'mcd':
      return (
        <g>
          <path d="M6 12H24" stroke="var(--encre)" strokeOpacity="0.6" strokeWidth="1" />
          {[1, 20].map((x) => (
            <g key={x}>
              <rect x={x} y="6" width="9" height="12" rx="1.5" fill={papier} />
              <rect x={x} y="6" width="9" height="4" fill="var(--entite-fond)" />
              <rect x={x} y="6" width="9" height="12" rx="1.5" fill="none" stroke="var(--entite)" strokeWidth="1" />
            </g>
          ))}
          <rect x="9.5" y="8.5" width="11" height="7" rx="3.5" fill={papier} stroke="var(--association)" strokeWidth="1.2" />
        </g>
      )
    case 'mld':
      return (
        <g>
          {[[1, 1], [18, 10]].map(([x, y]) => (
            <g key={x}>
              <rect x={x} y={y} width="11" height="13" rx="1.5" fill={papier} />
              <rect x={x} y={y} width="11" height="4" fill="var(--entite-fond)" />
              <rect x={x + 2} y={y + 6.5} width="7" height="1.1" fill="var(--encre-3)" />
              <rect x={x + 2} y={y + 9.5} width="7" height="1.1" fill="var(--encre-3)" />
              <rect x={x} y={y} width="11" height="13" rx="1.5" fill="none" stroke="var(--entite)" strokeWidth="1" />
            </g>
          ))}
          <path d="M12 7H15V17H18" fill="none" stroke="var(--association)" strokeWidth="1.2" />
        </g>
      )
    case 'uml':
      return (
        <g>
          <rect x="5" y="1" width="20" height="22" fill={papier} />
          <rect x="5" y="1" width="20" height="6" fill="var(--entite)" fillOpacity="0.22" />
          <rect x="5" y="1" width="20" height="22" fill="none" stroke="var(--entite)" strokeWidth="1.3" />
          <path d="M5 7H25M5 16H25" stroke="var(--entite)" strokeWidth="1" />
          <rect x="8" y="9.4" width="12" height="1.3" fill="var(--encre-3)" />
          <rect x="8" y="12.4" width="12" height="1.3" fill="var(--encre-3)" />
          <rect x="8" y="18.9" width="9" height="1.3" fill="var(--encre-3)" />
        </g>
      )
    case 'umlSimple':
      return (
        <g>
          <rect x="4" y="6" width="22" height="12" fill={papier} />
          <rect x="4" y="6" width="22" height="12" fill="var(--entite)" fillOpacity="0.22" stroke="var(--entite)" strokeWidth="1.3" />
          <rect x="9" y="11" width="12" height="2.2" rx="1" fill="var(--entite)" />
        </g>
      )
    case 'sql':
      return (
        <g>
          <path d="M6 4.5V19.5A9 3 0 0 0 24 19.5V4.5" fill="var(--association)" fillOpacity="0.2" stroke="var(--association)" strokeWidth="1.3" />
          <path d="M6 12A9 3 0 0 0 24 12" fill="none" stroke="var(--association)" strokeWidth="1.1" />
          <ellipse cx="15" cy="4.5" rx="9" ry="3" fill={papier} />
          <ellipse cx="15" cy="4.5" rx="9" ry="3" fill="var(--association)" fillOpacity="0.35" stroke="var(--association)" strokeWidth="1.3" />
        </g>
      )
  }
}
