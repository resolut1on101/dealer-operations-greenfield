import { existsSync } from 'node:fs'
import { execFileSync } from 'node:child_process'

const candidatePaths = [
  process.env.DOCKER_CLI_PATH,
  process.env.DOCKER_DESKTOP_CLI_PATH,
  'C:\\Users\\monds\\AppData\\Local\\Programs\\DockerDesktop\\resources\\bin\\docker.exe',
  'C:\\Program Files\\Docker\\Docker\\resources\\bin\\docker.exe',
  'C:\\Program Files\\Docker\\Docker\\resources\\docker.exe',
  'C:\\Program Files (x86)\\Docker\\Docker\\resources\\bin\\docker.exe',
  'C:\\Program Files (x86)\\Docker\\Docker\\resources\\docker.exe',
]

function hasExecutable(path) {
  return typeof path === 'string' && path.length > 0 && existsSync(path)
}

export function resolveDockerCommand() {
  for (const candidate of candidatePaths) {
    if (hasExecutable(candidate)) return candidate
  }

  try {
    const resolved = execFileSync('where.exe', ['docker'], { encoding: 'utf8' })
      .split(/\r?\n/)
      .map((line) => line.trim())
      .find((line) => line.length > 0)
    if (hasExecutable(resolved)) return resolved
  } catch {
    // Fall through to a clear error below.
  }

  throw new Error(
    'Docker CLI not found. Install Docker Desktop CLI or set DOCKER_CLI_PATH to the docker.exe path.',
  )
}
