# Environment and Release Runbook

## Environment isolation

`local`, `dev` and `live` use distinct Supabase projects/instances and distinct environment files/secrets. A command targeting a remote project must name its target explicitly; no script may infer `live` from a default link.

## Local

1. Start a Docker-compatible runtime.
2. Run `npm run supabase -- start`.
3. Copy the reported local URL and publishable key to `.env.local`.
4. Run `npm run supabase -- db reset --local` to validate all migrations from a clean database.

## First-admin concurrency guarantee

`bootstrap_first_admin(exact_user_uuid)` takes a deterministic, transaction-scoped PostgreSQL advisory lock before it checks for an existing admin. Calls for different target UUIDs are globally serialized: one transaction can create the first admin, and a waiting concurrent transaction rechecks after the lock is released and fails because an admin now exists. The procedure remains service-role-only and idempotent for the same already-admin UUID.

`npm run test:rls` runs the version-controlled `scripts/test-first-admin-concurrency.mjs` integration test after the RLS foundation test. It opens two independent local PostgreSQL sessions; the first holds the same advisory lock while it bootstraps the first target, and the second attempts a different target concurrently. The expected result is exactly one `admin` and one rejected call.

## Dev and live

1. Link the intended remote project explicitly with its project ref.
2. Verify the environment name, migration list and backup checkpoint requirement.
3. Run the CI checks locally/through CI.
4. Push migrations only to the verified target.
5. Deploy the static web build with the matching environment variables.

Live deployment and package release-state records begin in Package 00C. Package 00 does not deploy a user-facing application.

## İlk admin bootstrap sözleşmesi

1. Kullanıcı önce normal Auth kaydı ile oluşturulur. `auth.users` insert trigger’ı aynı UUID ile `public.user_profiles` kaydını deterministik olarak oluşturur ve rolü `viewer` olur.
2. Operatör, kullanıcıdan/onaylı kimlik kaynağından **tam Auth user UUID** değerini alır; e-posta adıyla veya tahminle admin atanmaz.
3. Yalnız trusted server-side `service_role` bağlamı `select public.bootstrap_first_admin('<exact-user-uuid>');` çağrısını yapabilir. `service_role` browser bundle’a, `.env.example`a veya client değişkenlerine konmaz.
4. Prosedür hedef profil yoksa hata verir; aynı kullanıcı zaten admin ise `admin` döndürerek idempotent kalır; başka bir admin varsa hata verir. Böylece yanlış kullanıcıya sessiz admin vermez ve ikinci admin ataması için ayrı, denetlenebilir operasyon gerekir.
5. Bu çağrı local testte doğrulanır. Gerçek dev/live çağrısı ancak kullanıcı exact UUID’yi ve hedef ortamı yazılı olarak sağladıktan sonra, explicit remote project link ile yapılır. Paket 00’da keyfi remote admin oluşturulmaz.

Tarayıcıdaki authenticated kullanıcılar yalnız `authenticated_read` politikasına sahiptir; kendi rollerini değiştiremez. `admin_write` yalnız mevcut admin’in mutation işlemleri için geçerlidir.
