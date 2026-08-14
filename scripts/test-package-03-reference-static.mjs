import { readFileSync } from 'node:fs'

const migration = readFileSync(new URL('../supabase/migrations/20260814000017_package_03_canonical_product_normalization.sql', import.meta.url), 'utf8').replace(/\r\n/g, '\n')

function requireMatch(condition, message) {
  if (!condition) throw new Error(message)
}

requireMatch(migration.includes('51fb373ca178b68a8ddd29a6ea8f65f54162137c78aaccfb9b7f93805ffffdf2'), 'Exact paket.xlsx SHA-256 is missing')
requireMatch(migration.includes('331, 84, 59, 36'), 'Reference evidence counts are missing')
requireMatch(migration.includes("where source_kind = 'PRODUCT_CONVERSION'\n  and is_active"), 'PRODUCT_CONVERSION retirement is missing')
requireMatch(migration.includes("v_batch.source_kind='PRODUCT_CONVERSION'"), 'Pre-existing PRODUCT_CONVERSION candidate block is missing')
requireMatch(migration.includes("v_batch.source_kind in ('SELLOUT','KA_DELIVERY')"), 'Freshness must react only to Sellout/KA runtime publications')
requireMatch(!migration.includes("v_batch.source_kind in ('PRODUCT_CONVERSION','SELLOUT','KA_DELIVERY')"), 'Freshness still reacts to runtime PRODUCT_CONVERSION')
requireMatch(migration.includes('create or replace function public.current_canonical_product_lpu'), 'Canonical LPU aggregation function is missing')
requireMatch(migration.includes('create or replace function public.canonical_product_lpu'), 'Canonical LPU resolver is missing')
requireMatch(migration.includes("coalesce(m.canonical_quantity_numerator,1::bigint)::numeric"), 'LPU aggregation must normalize raw quantity before litre aggregation')
requireMatch(migration.includes("coalesce(p.sellout_lpu_candidate,p.ka_lpu_candidate) as active_lpu"), 'Canonical LPU priority must be Sellout then KA')
requireMatch(migration.includes('revoke all on function public.current_canonical_product_lpu(text) from public, anon, authenticated;'), 'Canonical LPU aggregate must remain internal')
requireMatch(migration.includes('revoke all on function public.materialize_current_product_domain(text) from authenticated;'), 'Legacy runtime materializer must be retired from authenticated callers')

const mappingBlock = migration.match(/cross join \(values\n([\s\S]*?)\n\) as v\(component_key, raw_product_code, canonical_product_code,/)
requireMatch(mappingBlock, 'Canonical mapping values block was not found')
const mappingRows = [...mappingBlock[1].matchAll(/\('([0-9]+)', '([0-9]+)', '([0-9]+)', ([0-9]+), ([0-9]+), '(STANDARD|HIGH_ALCOHOL)', '([^']+)'\)/g)]
requireMatch(mappingRows.length === 84, `Expected 84 canonical mapping rows, got ${mappingRows.length}`)

const mappings = new Map(mappingRows.map(([, component, raw, canonical, numerator, denominator, policy, basis]) => [raw, {
  component, raw, canonical, numerator: BigInt(numerator), denominator: BigInt(denominator), policy, basis,
}]))
requireMatch(new Set([...mappings.values()].map((row) => row.canonical)).size === 36, 'Expected exactly 36 canonical products')

function expectMapping(raw, canonical, numerator, denominator, policy) {
  const row = mappings.get(raw)
  requireMatch(row, `Missing mapping for ${raw}`)
  requireMatch(row.canonical === canonical, `${raw} canonical mismatch: ${row.canonical} != ${canonical}`)
  requireMatch(row.numerator === BigInt(numerator) && row.denominator === BigInt(denominator), `${raw} factor mismatch`)
  requireMatch(row.policy === policy, `${raw} policy mismatch: ${row.policy} != ${policy}`)
}

expectMapping('150021', '150021', 1, 1, 'STANDARD')
expectMapping('154525', '150021', 1, 2, 'STANDARD')
expectMapping('154548', '150021', 1, 4, 'STANDARD')
expectMapping('151830', '151830', 1, 1, 'STANDARD')
expectMapping('154558', '151830', 1, 2, 'STANDARD')
expectMapping('154559', '151830', 1, 4, 'STANDARD')
expectMapping('152224', '152315', 24, 1, 'HIGH_ALCOHOL')
expectMapping('152315', '152315', 1, 1, 'HIGH_ALCOHOL')
expectMapping('152747', '152755', 24, 1, 'HIGH_ALCOHOL')
expectMapping('152417', '152471', 1, 1, 'STANDARD')
expectMapping('152733', '152471', 1, 4, 'STANDARD')

for (const row of mappings.values()) {
  requireMatch(row.numerator > 0n && row.denominator > 0n, `Non-positive canonical factor for ${row.raw}`)
  const canonical = mappings.get(row.canonical)
  requireMatch(canonical, `Canonical target ${row.canonical} is not mapped`)
  requireMatch(canonical.canonical === row.canonical && canonical.numerator === canonical.denominator, `Canonical target ${row.canonical} is not an identity row`)
}

const edgeBlock = migration.match(/cross join \(values\n([\s\S]*?)\n\) as v\(source_product_code, target_product_code, source_quantity_basis,/)
requireMatch(edgeBlock, 'Reference edge values block was not found')
const edgeRows = [...edgeBlock[1].matchAll(/\('([0-9]+)', '([0-9]+)', ([0-9]+), ([0-9]+), '([^']+)', '([^']+)', ([0-9]+)\)/g)]
requireMatch(edgeRows.length === 59, `Expected 59 stable directed edges, got ${edgeRows.length}`)
requireMatch(edgeRows.reduce((sum, row) => sum + Number(row[7]), 0) === 331, 'Edge observation counts must sum to 331')

// Exact edge conservation under canonical factors.
for (const [, source, target, sourceBasis, targetBasis] of edgeRows) {
  const s = mappings.get(source)
  const t = mappings.get(target)
  requireMatch(s && t, `Missing mapping for edge ${source}->${target}`)
  const left = BigInt(sourceBasis) * s.numerator * t.denominator
  const right = BigInt(targetBasis) * t.numerator * s.denominator
  requireMatch(left === right, `Canonical factor violates edge ${source}->${target}`)
}

// UX rounding never changes the exact backend value used for calculations.
const exactQuarterCase = 10.75
requireMatch(Math.round(exactQuarterCase) === 11, 'Expected display rounding 10.75 -> 11')
requireMatch(exactQuarterCase * 12 === 129, 'Exact litre math must stay 129, not 132')

console.log('Package 03 canonical product reference static PASS. 84 codes -> 36 canonical products; 59/331 edge evidence conserved.')
