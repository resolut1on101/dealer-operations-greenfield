import {
  applicationEnvironmentSchema,
  packageIdentifierSchema,
  releaseStateSchema,
} from '@dealer-operations/contracts'

export const applicationEnvironment = applicationEnvironmentSchema.parse(
  import.meta.env.VITE_APP_ENV ?? 'local',
)

const rawReleaseState = import.meta.env.VITE_RELEASE_STATE ?? 'BLOCKED'

export const releaseState = releaseStateSchema.parse(rawReleaseState)
export const releasePackage = packageIdentifierSchema.parse(
  import.meta.env.VITE_RELEASE_PACKAGE ?? '03AU',
)
export const buildVersion = import.meta.env.VITE_BUILD_VERSION ?? 'dev'
export const databaseMigrationVersion = import.meta.env.VITE_DB_MIGRATION_VERSION ?? '20260814000019'

export const supabaseConfiguration = {
  url: import.meta.env.VITE_SUPABASE_URL,
  publishableKey: import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY,
}

export const isSupabaseConfigured = Boolean(
  supabaseConfiguration.url && supabaseConfiguration.publishableKey,
)

if (applicationEnvironment === 'live' && !isSupabaseConfigured) {
  throw new Error('Live releases require a Supabase URL and publishable key.')
}

if (applicationEnvironment === 'live' && releaseState === 'BLOCKED') {
  throw new Error('A live release must declare LIVE_TESTING or VERIFIED.')
}
