import { useState, type FormEvent } from 'react'
import { Navigate } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import { useAuth } from '../auth/AuthContext'
import { supabase, isConfigured } from '../lib/supabase'
import LanguagePicker from '../components/LanguagePicker'
import NotConfigured from './NotConfigured'

export default function Login() {
  const { t } = useTranslation()
  const { session } = useAuth()
  const [mode, setMode] = useState<'signin' | 'signup'>('signin')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState<{ kind: 'error' | 'info'; text: string } | null>(null)

  if (!isConfigured || !supabase) return <NotConfigured />
  if (session) return <Navigate to="/" replace />

  async function submit(event: FormEvent) {
    event.preventDefault()
    if (!supabase) return
    setMessage(null)

    if (password.length < 8) {
      setMessage({ kind: 'error', text: t('auth.errorShortPassword') })
      return
    }

    setBusy(true)
    try {
      if (mode === 'signin') {
        const { error } = await supabase.auth.signInWithPassword({ email, password })
        if (error) {
          const invalid = error.message.toLowerCase().includes('invalid')
          setMessage({ kind: 'error', text: t(invalid ? 'auth.errorInvalid' : 'auth.errorGeneric') })
        }
      } else {
        const { data, error } = await supabase.auth.signUp({ email, password })
        if (error) {
          setMessage({ kind: 'error', text: t('auth.errorGeneric') })
        } else if (!data.session) {
          setMessage({ kind: 'info', text: t('auth.checkEmail') })
        }
      }
    } catch {
      setMessage({ kind: 'error', text: t('auth.errorGeneric') })
    } finally {
      setBusy(false)
    }
  }

  const signingIn = mode === 'signin'

  return (
    <div className="center-screen">
      <div className="card narrow">
        <div className="logo-large" aria-hidden="true">
          M
        </div>
        <h1>{t(signingIn ? 'auth.titleSignIn' : 'auth.titleSignUp')}</h1>
        <p className="muted">{t('app.tagline')}</p>

        <form onSubmit={submit} className="form">
          <label>
            <span>{t('auth.email')}</span>
            <input
              type="email"
              autoComplete="email"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
            />
          </label>
          <label>
            <span>{t('auth.password')}</span>
            <input
              type="password"
              autoComplete={signingIn ? 'current-password' : 'new-password'}
              required
              minLength={8}
              value={password}
              onChange={(e) => setPassword(e.target.value)}
            />
            {!signingIn && <small className="muted">{t('auth.passwordHint')}</small>}
          </label>

          {message && <p className={message.kind === 'error' ? 'notice error' : 'notice info'}>{message.text}</p>}

          <button className="primary" type="submit" disabled={busy}>
            {busy ? t('auth.working') : t(signingIn ? 'auth.submitSignIn' : 'auth.submitSignUp')}
          </button>
        </form>

        <button
          type="button"
          className="link"
          onClick={() => {
            setMode(signingIn ? 'signup' : 'signin')
            setMessage(null)
          }}
        >
          {t(signingIn ? 'auth.switchToSignUp' : 'auth.switchToSignIn')}
        </button>

        <LanguagePicker compact />
      </div>
    </div>
  )
}
