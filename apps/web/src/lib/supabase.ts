import { createClient } from '@supabase/supabase-js'
import { isSupabaseConfigured, supabaseConfiguration } from './environment'

export const supabase = isSupabaseConfigured
  ? createClient(supabaseConfiguration.url!, supabaseConfiguration.publishableKey!, {
      auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
    })
  : null
