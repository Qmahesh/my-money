import { useTranslation } from 'react-i18next'
import { useHousehold } from '../household/HouseholdContext'

export default function Home() {
  const { t } = useTranslation()
  const { household } = useHousehold()
  const upcoming = ['c1', 'c2', 'c3', 'c4'] as const
  return (
    <>
      <section className="card hero">
        <h1>{t('home.welcome')}</h1>
        <p>{t('home.subtitle')}</p>
        {household && (
          <p>
            {household.name} · {t(`roles.${household.role}`)}
          </p>
        )}
      </section>

      <section className="card">
        <h2>{t('home.comingTitle')}</h2>
        <ul className="checklist">
          {upcoming.map((key) => (
            <li key={key}>{t(`home.${key}`)}</li>
          ))}
        </ul>
      </section>
    </>
  )
}
