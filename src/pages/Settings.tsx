import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { useAuth } from '../auth/AuthContext'
import { useHousehold } from '../household/HouseholdContext'
import LanguagePicker from '../components/LanguagePicker'
import { checkConnection, isConfigured } from '../lib/supabase'
import { APP_VERSION } from '../version'

type Status = 'checking' | 'connected' | 'unreachable' | 'unconfigured'

export default function Settings() {
  const { t } = useTranslation()
  const { session, signOut } = useAuth()
  const { household } = useHousehold()
  const [status, setStatus] = useState<Status>(isConfigured ? 'checking' : 'unconfigured')

  useEffect(() => {
    if (!isConfigured) return
    let active = true
    checkConnection().then((ok) => {
      if (active) setStatus(ok ? 'connected' : 'unreachable')
    })
    return () => {
      active = false
    }
  }, [])

  const statusText: Record<Status, string> = {
    checking: t('settings.checking'),
    connected: t('settings.connected'),
    unreachable: t('settings.notConnected'),
    unconfigured: t('settings.notConfigured'),
  }

  return (
    <>
      <h1 className="page-title">{t('settings.title')}</h1>

      <section className="card">
        <h2>{t('settings.language')}</h2>
        <LanguagePicker />
      </section>

      {household && (
        <section className="card">
          <h2>{t('settings.household')}</h2>
          <p>
            {household.name} · {t(`roles.${household.role}`)}
          </p>
        </section>
      )}

      <section className="card">
        <h2>{t('settings.connection')}</h2>
        <p>
          <span className={`dot ${status}`} aria-hidden="true" /> {statusText[status]}
        </p>
      </section>

      <section className="card">
        <h2>{t('settings.account')}</h2>
        {session?.user.email && <p>{t('settings.signedInAs', { email: session.user.email })}</p>}
        <button className="secondary" type="button" onClick={signOut}>
          {t('settings.signOut')}
        </button>
      </section>

      <p className="muted center">{t('settings.version', { version: APP_VERSION })}</p>
    </>
  )
}
