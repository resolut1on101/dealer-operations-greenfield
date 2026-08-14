import { describe, expect, it } from 'vitest'
import { disambiguateSourceHeaders, parseSourceMatrix, sourceHeaderSignatureMatches } from './source-parser'

describe('source workbook header preservation', () => {
  it('keeps duplicate Excel headers as deterministic positional aliases', () => {
    expect(disambiguateSourceHeaders([
      'Bozulan/Birleştirilen Ürün Kodu', 'Miktar', 'Temel ölçü birimi',
      'Oluşan Ürün Kodu', 'Miktar', 'Temel ölçü birimi',
    ])).toEqual([
      'Bozulan/Birleştirilen Ürün Kodu', 'Miktar', 'Temel ölçü birimi',
      'Oluşan Ürün Kodu', 'Miktar__2', 'Temel ölçü birimi__2',
    ])
  })

  it('maps both conversion quantities to their own payload fields instead of overwriting the first value', () => {
    const parsed = parseSourceMatrix([
      ['Bozulan/Birleştirilen Ürün Kodu', 'Miktar', '', 'Oluşan Ürün Kodu', 'Miktar'],
      [150487, 5, 'ignored', 154505, 20],
    ])

    expect(parsed.headers).toEqual(['Bozulan/Birleştirilen Ürün Kodu', 'Miktar', 'Oluşan Ürün Kodu', 'Miktar__2'])
    expect(parsed.rows).toEqual([{
      'Bozulan/Birleştirilen Ürün Kodu': 150487,
      Miktar: 5,
      'Oluşan Ürün Kodu': 154505,
      Miktar__2: 20,
    }])
  })



  it('requires the exact three-column Malzemeler signature for WAREHOUSE_STOCK', () => {
    const expected = ['Malzeme numarası', 'Malzeme tanımı', 'Tahditsiz kullanılabilir']
    expect(sourceHeaderSignatureMatches(expected, expected, true)).toBe(true)
    expect(sourceHeaderSignatureMatches([...expected, 'Unexpected'], expected, true)).toBe(false)
    expect(sourceHeaderSignatureMatches([expected[1], expected[0], expected[2]], expected, true)).toBe(false)
    expect(sourceHeaderSignatureMatches([...expected, 'Unexpected'], expected, false)).toBe(true)
  })

  it('leaves existing unique source contracts unchanged', () => {
    const parsed = parseSourceMatrix([
      ['Müşteri', 'Müşteri Adı'],
      ['500001', 'Alpha'],
    ])
    expect(parsed.headers).toEqual(['Müşteri', 'Müşteri Adı'])
    expect(parsed.rows[0]).toEqual({ Müşteri: '500001', 'Müşteri Adı': 'Alpha' })
  })
})
