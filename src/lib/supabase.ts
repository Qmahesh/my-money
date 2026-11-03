import { createClient, type SupabaseClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL
const key = import.meta.env.VITE_SUPABASE_ANON_KEY

/** True when both environment variables are present. */
export const isConfigured = Boolean(url && key)

/** The Supabase client, or null while the app has not been configured yet. */
export const supabase: SupabaseClient | null =
  url && key ? createClient(url, key) : null

/** Quick health check used on the Settings screen. */
export async function checkConnection(): Promise<boolean> {
  if (!url || !key) return false
  try {
    const response = await fetch(`${url}/auth/v1/health`, { headers: { apikey: key } })
    return response.ok
  } catch {
    return false
  }
}
