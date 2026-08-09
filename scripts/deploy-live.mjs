import { spawnSync } from 'node:child_process';

const required = [
  'VITE_SUPABASE_URL',
  'VITE_SUPABASE_PUBLISHABLE_KEY',
  'VITE_BUILD_VERSION',
  'VITE_DB_MIGRATION_VERSION',
];
const missing = required.filter((name) => !process.env[name]);
if (process.env.VITE_APP_ENV !== 'live' || process.env.VITE_RELEASE_STATE !== 'LIVE_TESTING') {
  throw new Error('First live deploy requires VITE_APP_ENV=live and VITE_RELEASE_STATE=LIVE_TESTING.');
}
if (missing.length > 0) throw new Error(`Live deploy is missing required environment variables: ${missing.join(', ')}`);

function run(command, args) {
  if (process.platform === 'win32') {
    return spawnSync(process.env.ComSpec ?? 'cmd.exe', ['/d', '/s', '/c', `${command} ${args.join(' ')}`], { stdio: 'inherit' });
  }
  return spawnSync(command, args, { stdio: 'inherit' });
}

const verify = run('npm', ['run', 'verify']);
if (verify.status !== 0) process.exit(verify.status ?? 1);
const deploy = run('npx', ['wrangler', 'pages', 'deploy', 'apps/web/dist', '--project-name', 'dealer-operations-greenfield', '--branch', 'main']);
process.exit(deploy.status ?? 1);
