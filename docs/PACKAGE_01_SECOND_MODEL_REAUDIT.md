# Package 01 Narrow Second-Model Re-Audit

**Basis:** `PACKAGE_01_SECOND_MODEL_AUDIT.md` and `PACKAGE_01_AUDIT_REMEDIATION_REPORT.md`.

**Scope:** immutable source-contract provenance, reconciliation retry/idempotency, first-submission chunk hash integrity, server-bound Storage path, atomic publication, concurrency, RLS/admin mutations, and failed-publish preservation only.

**Result:** `BLOCKED`

## Blocker

### AUD-04 remains unresolved — Storage UPDATE can escape the server-bound path

The batch path is server generated and `INSERT` correctly requires it to match an unverified batch owned by the authenticated admin. However, `source_evidence_admin_update` checks that binding only in its `USING` predicate (the existing row). Its `WITH CHECK` clause validates only the bucket and admin role; it does not require the **new** `storage.objects.name` to equal a batch's generated `storage_object_path`.

A rollback-only local RLS test created a valid batch/object as an authenticated admin, then successfully executed:

```sql
update storage.objects
set name = 'client-controlled/unbound.xlsx'
where bucket_id = 'source-evidence' and name = <generated batch path>;
```

The update affected one row and the transaction was rolled back. This proves that a client can rename a bound source-evidence object to an arbitrary path. The claim that Storage write policies enforce the batch/object path is therefore false, and Package 01 cannot receive `AUDIT_PASS`.

Evidence: `supabase/migrations/20260809000007_package_01_audit_fixes.sql`, policy `source_evidence_admin_update`.

## Controls re-verified as passing

- **AUD-01:** Same source-contract version is idempotent only for identical content; changed content fails, and the trigger blocks direct mutation after a batch uses the contract.
- **AUD-02:** Repeated reconciliation returns the persisted reconciliation ID without deleting a referenced row.
- **AUD-03:** Staging rejects a first submission when the declared chunk hash differs from the server canonical SHA-256 payload digest.
- **Atomic publication and concurrency:** advisory lock plus expected active-head check prevents two active versions; the existing two-session regression passes.
- **RLS/admin mutations:** import mutation RPCs assert admin identity; direct import-table mutation remains unavailable to authenticated callers.
- **Failed publish preservation:** stale publish is rejected before head change; the prior active publication remains intact in integration coverage.

## Disposition

Do not prepare or perform live deployment. Fix the `UPDATE ... WITH CHECK` path-binding gap and add a regression test that proves a rename to an unbound path is denied. Then repeat this same narrow audit. No code was changed during this re-audit.
