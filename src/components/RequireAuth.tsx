import { Navigate } from 'react-router-dom'
import type { ReactElement } from 'react'
import { useTranslation } from 'react-i18next'
import { useAuth } from '../auth/AuthContext'
import { useHousehold } from '../household/HouseholdContext'
import { isConfigured } from '../lib/supabase'
import NotConfigured from '../pages/NotConfigured'

export default function RequireAuth({ children }: { children: ReactElement }) {
  const { session, loading } = useAuth()
  const { household, loading: householdLoading, failed, retry } = useHousehold()
  const { t } = useTranslation()

  if (!isConfigured) return <NotConfigured />
  if (loading) return <div className="center-screen">{t('common.loading')}</div>
  if (!session) return <Navigate to="/login" replace />

  if (failed) {
    return (
      <div className="center-screen">
        <div className="card narrow">
          <p>{t('household.loadError')}</p>
          <button className="primary" type="button" onClick={retry}>
            {t('household.retry')}
          </button>
        </div>
      </div>
    )
  }
  if (householdLoading || !household) return <div className="center-screen">{t('common.loading')}</div>

  return children
}
