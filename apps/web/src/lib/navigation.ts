import type { ApplicationRole } from '@dealer-operations/contracts'

export type NavGroup = { label: string; items: string[] }

const mutationOnlyItems = new Set(['Veri Yükleme', 'Ayarlar'])

const navGroups: NavGroup[] = [
  { label: 'GENEL', items: ['Genel Bakış'] },
  { label: 'SATIŞ & MÜŞTERİ', items: ['Müşteriler', 'Sellout', 'FKNS'] },
  { label: 'STOK & PLANLAMA', items: ['Depo Stoku', 'Ticari Stok', 'Talep & Sipariş Planlama'] },
  { label: 'OPERASYON', items: ['Siparişler', 'Sevkiyat', 'Fatura Kontrol'] },
  { label: 'FİNANS', items: ['Cari 360', 'Tahsilatlar', 'Çek / Senet', 'Finansal Analiz'] },
  { label: 'ANALİZ', items: ['Rapor Merkezi', 'AI Asistan'] },
  { label: 'YÖNETİM', items: ['Veri Yükleme', 'Sistem Sağlığı', 'Ayarlar'] },
]

export function getVisibleNavGroups(role: ApplicationRole | null): NavGroup[] {
  if (role === 'admin') return navGroups
  return navGroups
    .map((group) => ({ ...group, items: group.items.filter((item) => !mutationOnlyItems.has(item)) }))
    .filter((group) => group.items.length > 0)
}
