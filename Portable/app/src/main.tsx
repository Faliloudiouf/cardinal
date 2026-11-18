import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import './mise-en-page.css'
import './ui/diagramme.css'
import App from './App'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
