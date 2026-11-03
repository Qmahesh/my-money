import { NavLink, Outlet, Link } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import { Icon, type IconName } from './Icons'

const tabs: { to: string; key: string; icon: IconName; end?: boolean }[] = [
  { to: '/', key: 'home', icon: 'home', end: true },
  { to: '/add', key: 'add', icon: 'add' },
  { to: '/bills', key: 'bills', icon: 'bills' },
  { to: '/accounts', key: 'accounts', icon: 'accounts' },
  { to: '/reports', key: 'reports', icon: 'reports' },
]

export default function Layout() {
  const { t } = useTranslation()
  return (
    <div className="shell">
      <header className="topbar">
        <span className="brand">
          <span className="brand-mark" aria-hidden="true">
            M
          </span>
          {t('app.name')}
        </span>
        <Link to="/settings" className="icon-button" aria-label={t('nav.settings')}>
          <Icon name="settings" size={22} />
        </Link>
      </header>

      <main className="content">
        <Outlet />
      </main>

      <nav className="tabbar" aria-label="Main">
        {tabs.map((tab) => (
          <NavLink
            key={tab.to}
            to={tab.to}
            end={tab.end}
            className={({ isActive }) => (isActive ? 'tab active' : 'tab')}
          >
            <Icon name={tab.icon} />
            <span>{t(`nav.${tab.key}`)}</span>
          </NavLink>
        ))}
      </nav>
    </div>
  )
}
