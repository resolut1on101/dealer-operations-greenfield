import { applicationEnvironment } from './lib/environment'

export function App() {
  return (
    <main className="technical-foundation" aria-labelledby="page-title">
      <h1 id="page-title">Teknik temel hazır</h1>
      <p>Ürün ekranları ve tasarım sistemi Paket 00B’nin kapsamındadır.</p>
      <dl>
        <div><dt>Ortam</dt><dd>{applicationEnvironment}</dd></div>
        <div><dt>Build</dt><dd>{import.meta.env.VITE_BUILD_VERSION ?? 'dev'}</dd></div>
      </dl>
    </main>
  )
}
