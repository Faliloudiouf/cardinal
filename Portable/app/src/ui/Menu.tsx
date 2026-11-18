// Menu déroulant léger, ouvert depuis un bouton (clavier : flèches, Entrée, Échap).
import { useEffect, useRef, useState, type ReactNode } from 'react'

export interface ElementMenu {
  libelle: string
  action?: () => void
  raccourci?: string
  coche?: boolean
  desactive?: boolean
  titre?: boolean
  separateur?: boolean
}

export function Menu({ elements, children, className, titre }: {
  elements: ElementMenu[] | (() => ElementMenu[])
  children: ReactNode
  className?: string
  titre?: string
}) {
  const [ouvert, setOuvert] = useState(false)
  const [place, setPlace] = useState({ top: 0, left: 0 })
  const racine = useRef<HTMLDivElement>(null)
  const liste = ouvert ? (typeof elements === 'function' ? elements() : elements) : []

  useEffect(() => {
    if (!ouvert) return
    const fermer = (e: PointerEvent) => {
      if (!racine.current?.contains(e.target as Node)) setOuvert(false)
    }
    const touche = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setOuvert(false)
    }
    window.addEventListener('pointerdown', fermer, true)
    window.addEventListener('keydown', touche)
    requestAnimationFrame(() => racine.current?.querySelector<HTMLButtonElement>('.menu-liste button:not(:disabled)')?.focus())
    return () => {
      window.removeEventListener('pointerdown', fermer, true)
      window.removeEventListener('keydown', touche)
    }
  }, [ouvert])

  function naviguer(e: React.KeyboardEvent) {
    if (e.key !== 'ArrowDown' && e.key !== 'ArrowUp') return
    e.preventDefault()
    const boutons = [...(racine.current?.querySelectorAll<HTMLButtonElement>('.menu-liste button:not(:disabled)') ?? [])]
    const i = boutons.indexOf(document.activeElement as HTMLButtonElement)
    boutons[(i + (e.key === 'ArrowDown' ? 1 : boutons.length - 1)) % boutons.length]?.focus()
  }

  return (
    <div className={`menu ${className ?? ''}`} ref={racine}>
      <button className="menu-declencheur" aria-haspopup="menu" aria-expanded={ouvert} title={titre} onClick={(e) => {
        // Le ruban défile horizontalement : le menu est placé en position fixe sous le bouton.
        const b = (e.currentTarget.closest('.bouton-double') ?? e.currentTarget).getBoundingClientRect()
        setPlace({ top: b.bottom + 4, left: Math.min(b.left, window.innerWidth - 250) })
        setOuvert((o) => !o)
      }}>
        {children}
      </button>
      {ouvert && (
        <div className="menu-liste" role="menu" onKeyDown={naviguer} style={place}>
          {liste.map((el, i) =>
            el.separateur ? <div key={i} className="menu-separateur" role="separator" />
              : el.titre ? <div key={i} className="menu-titre">{el.libelle}</div>
                : (
                  <button
                    key={i} role="menuitemcheckbox" aria-checked={el.coche ?? false} disabled={el.desactive}
                    onClick={() => { setOuvert(false); el.action?.() }}
                  >
                    <span className="menu-coche">{el.coche ? '✓' : ''}</span>
                    <span className="menu-libelle">{el.libelle}</span>
                    {el.raccourci && <span className="menu-raccourci">{el.raccourci}</span>}
                  </button>
                ),
          )}
        </div>
      )}
    </div>
  )
}
