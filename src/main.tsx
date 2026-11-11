import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { BrowserRouter } from 'react-router-dom'
import './i18n'
import './styles.css'
import App from './App'
import { AuthProvider } from './auth/AuthContext'
import { HouseholdProvider } from './household/HouseholdContext'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <BrowserRouter>
      <AuthProvider>
        <HouseholdProvider>
          <App />
        </HouseholdProvider>
      </AuthProvider>
    </BrowserRouter>
  </StrictMode>,
)
