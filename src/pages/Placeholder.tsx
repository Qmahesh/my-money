import { useTranslation } from 'react-i18next'

export default function Placeholder({ titleKey }: { titleKey: string }) {
  const { t } = useTranslation()
  return (
    <section className="card">
      <h1>{t(titleKey)}</h1>
      <p className="muted">{t('placeholder.comingSoon')}</p>
      <p className="muted">{t('placeholder.plannedFor')}</p>
    </section>
  )
}
