import { useTranslation } from 'react-i18next'

export default function NotConfigured() {
  const { t } = useTranslation()
  return (
    <div className="center-screen">
      <div className="card narrow">
        <div className="logo-large" aria-hidden="true">
          M
        </div>
        <h1>{t('setup.title')}</h1>
        <p className="muted">{t('setup.body')}</p>
      </div>
    </div>
  )
}
