import { Navigate } from 'react-router-dom'
import type { ReactElement } from 'react'
import { useTranslation } from 'react-i18next'
import { useAuth } from '../auth/AuthContext'
import { isConfigured } from '../lib/supabase'
import NotConfigured from '../pages/NotConfigured'

export default function RequireAuth({ children }: { children: ReactElement }) {
  const { session, loading } = useAuth()
  const { t } = useTranslation()

  if (!isConfigured) return <NotConfigured />
  if (loading) return <div className="center-screen">{t('common.loading')}</div>
  if (!session) return <Navigate to="/login" replace />
  return children
}
