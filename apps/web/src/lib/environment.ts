import { applicationEnvironmentSchema } from '@dealer-operations/contracts'

export const applicationEnvironment = applicationEnvironmentSchema.parse(
  import.meta.env.VITE_APP_ENV ?? 'local',
)
