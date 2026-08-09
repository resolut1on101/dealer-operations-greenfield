import { execFileSync, spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, rmSync } from 'node:fs';
import { join } from 'node:path';

const repoRoot = process.cwd();
const outputDirectory = join(repoRoot, 'artifacts', 'review');
const forbiddenPaths = [
  /^\.git(?:\/|$)/,
  /^node_modules(?:\/|$)/,
  /^dist(?:\/|$)/,
  /^coverage(?:\/|$)/,
  /^playwright-report(?:\/|$)/,
  /^test-results(?:\/|$)/,
  /^supabase\/\.temp(?:\/|$)/,
  /(?:^|\/)\.env(?:$|\.)/,
  /(?:^|\/)(?:cache|temp)(?:\/|$)/i,
  /\.log$/i,
];

const secretPatterns = [
  { name: 'private key', pattern: /-----BEGIN (?:[A-Z ]*PRIVATE KEY|OPENSSH PRIVATE KEY)-----/ },
  { name: 'JWT-like secret', pattern: /(?:^|[^A-Za-z0-9_-])eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}/ },
  {
    name: 'non-empty secret assignment',
    pattern: /^\s*(?:export\s+)?(?:SUPABASE_SERVICE_ROLE_KEY|SERVICE_ROLE_KEY|SUPABASE_SECRET_KEY|SUPABASE_ANON_KEY|ANON_KEY|GEMINI_API_KEY|OPENAI_API_KEY|API_SECRET|PRIVATE_KEY|JWT_SECRET|INTERNAL_SECRET|INTERNAL_API_KEY|INTERNAL_KEY)\s*[:=]\s*(?!['"]?\s*(?:$|#))['"]?[^'"\s#]+/im,
  },
];

function git(args, options = {}) {
  return execFileSync('git', args, { cwd: repoRoot, encoding: 'utf8', ...options });
}

function assertCleanTrackedTree() {
  for (const args of [['diff', '--quiet', 'HEAD'], ['diff', '--cached', '--quiet']]) {
    const result = spawnSync('git', args, { cwd: repoRoot, encoding: 'utf8' });
    if (result.status !== 0) {
      throw new Error('Tracked çalışma ağacı temiz değil. Review ZIP yalnız commit edilmiş içerikten üretilir.');
    }
  }
}

function trackedFilesAtHead() {
  return git(['ls-tree', '-r', '--name-only', 'HEAD'])
    .split(/\r?\n/)
    .filter(Boolean);
}

function assertSafePaths(files) {
  const violations = files.filter((file) => file !== '.env.example' && forbiddenPaths.some((pattern) => pattern.test(file)));
  if (violations.length > 0) {
    throw new Error(`Review ZIP yasak dosya/yol içeriyor:\n${violations.join('\n')}`);
  }
}

function assertNoSecrets(files) {
  const findings = [];
  for (const file of files) {
    const content = execFileSync('git', ['show', `HEAD:${file}`], { cwd: repoRoot, encoding: 'utf8' });
    for (const { name, pattern } of secretPatterns) {
      if (pattern.test(content)) findings.push(`${file}: ${name}`);
    }
  }
  if (findings.length > 0) {
    throw new Error(`Secret scan başarısız; ZIP üretilmedi:\n${findings.join('\n')}`);
  }
}

assertCleanTrackedTree();
const files = trackedFilesAtHead();
assertSafePaths(files);
assertNoSecrets(files);

const sha = git(['rev-parse', '--short=12', 'HEAD']).trim();
const outputPath = join(outputDirectory, `dealer-operations-greenfield-${sha}.zip`);
mkdirSync(outputDirectory, { recursive: true });
if (existsSync(outputPath)) rmSync(outputPath);

const archive = spawnSync('git', ['archive', '--format=zip', '--output', outputPath, 'HEAD'], {
  cwd: repoRoot,
  encoding: 'utf8',
});
if (archive.status !== 0) {
  if (existsSync(outputPath)) rmSync(outputPath);
  throw new Error(archive.stderr || 'git archive başarısız oldu.');
}

console.log(`Review bundle PASS: ${outputPath}`);
console.log(`Secret scan PASS; excluded runtime paths PASS; commit ${sha}`);
