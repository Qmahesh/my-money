import { useTranslation } from 'react-i18next'
import { LANGUAGES } from '../i18n'

export default function LanguagePicker({ compact = false }: { compact?: boolean }) {
  const { i18n } = useTranslation()
  return (
    <div className={compact ? 'segmented compact' : 'segmented'} role="group" aria-label="Language">
      {LANGUAGES.map((lang) => (
        <button
          key={lang.code}
          type="button"
          className={i18n.language === lang.code ? 'seg active' : 'seg'}
          onClick={() => i18n.changeLanguage(lang.code)}
        >
          {lang.label}
        </button>
      ))}
    </div>
  )
}
