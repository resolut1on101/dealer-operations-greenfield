export type SourceMatrix = unknown[][]


export function sourceHeaderSignatureMatches(
  headers: string[],
  requiredHeaders: string[],
  exact = false,
) {
  if (exact) {
    return headers.length === requiredHeaders.length
      && headers.every((header, index) => header === requiredHeaders[index])
  }
  return requiredHeaders.every((header) => headers.includes(header))
}

export function disambiguateSourceHeaders(headerRow: unknown[]): string[] {
  const counts = new Map<string, number>()
  const used = new Set<string>()

  return headerRow.map((value) => {
    const base = String(value ?? '').trim()
    if (!base) return ''

    let occurrence = (counts.get(base) ?? 0) + 1
    counts.set(base, occurrence)

    let candidate = occurrence === 1 ? base : `${base}__${occurrence}`
    while (used.has(candidate)) {
      occurrence += 1
      counts.set(base, occurrence)
      candidate = `${base}__${occurrence}`
    }
    used.add(candidate)
    return candidate
  })
}

export function parseSourceMatrix(matrix: SourceMatrix) {
  const positionedHeaders = disambiguateSourceHeaders(matrix[0] ?? [])
  const headers = positionedHeaders.filter(Boolean)
  const rows = matrix
    .slice(1)
    .filter((row) => row.some((value) => value !== null && value !== undefined && String(value).trim() !== ''))
    .map((row) => Object.fromEntries(
      positionedHeaders.flatMap((header, index) => header ? [[header, row[index] ?? null] as const] : []),
    ))

  return { headers, rows }
}
