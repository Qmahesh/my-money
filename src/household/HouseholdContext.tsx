import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from 'react'
import { useTranslation } from 'react-i18next'
import { useAuth } from '../auth/AuthContext'
import { supabase } from '../lib/supabase'

export type Role = 'admin' | 'member'

export interface Household {
  id: string
  name: string
  role: Role
}

interface HouseholdState {
  household: Household | null
  loading: boolean
  failed: boolean
  retry: () => void
}

const HouseholdContext = createContext<HouseholdState>({
  household: null,
  loading: false,
  failed: false,
  retry: () => {},
})

/**
 * After sign-in, make sure the user has a household (the database function is
 * safe to call repeatedly) and load its name and the user's role.
 */
export function HouseholdProvider({ children }: { children: ReactNode }) {
  const { session } = useAuth()
  const { i18n } = useTranslation()
  const [household, setHousehold] = useState<Household | null>(null)
  const [loading, setLoading] = useState(false)
  const [failed, setFailed] = useState(false)
  const [attempt, setAttempt] = useState(0)

  const userId = session?.user.id ?? null
  const language = i18n.language

  useEffect(() => {
    if (!supabase || !userId) {
      setHousehold(null)
      setFailed(false)
      setLoading(false)
      return
    }
    const client = supabase
    let active = true
    setLoading(true)
    setFailed(false)

    async function load() {
      const created = await client.rpc('bootstrap_household', {
        p_name: 'My household',
        p_currency: 'SEK',
        p_language: language,
      })
      if (created.error) throw created.error

      const [members, households] = await Promise.all([
        client.from('household_members').select('role').eq('user_id', userId).single(),
        client.from('households').select('id, name').eq('id', created.data).single(),
      ])
      if (members.error) throw members.error
      if (households.error) throw households.error

      return {
        id: households.data.id as string,
        name: households.data.name as string,
        role: members.data.role as Role,
      }
    }

    load()
      .then((result) => {
        if (active) setHousehold(result)
      })
      .catch(() => {
        if (active) setFailed(true)
      })
      .finally(() => {
        if (active) setLoading(false)
      })

    return () => {
      active = false
    }
    // The language only matters the very first time (names the default account),
    // so it is intentionally not a dependency.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [userId, attempt])

  const retry = useCallback(() => setAttempt((n) => n + 1), [])

  return (
    <HouseholdContext.Provider value={{ household, loading, failed, retry }}>
      {children}
    </HouseholdContext.Provider>
  )
}

export function useHousehold() {
  return useContext(HouseholdContext)
}
