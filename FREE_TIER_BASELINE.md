# Supabase Free-Tier Baseline

**Verified:** 2026-08-09  
**Official source:** <https://supabase.com/pricing>

| Resource | Free baseline |
|---|---:|
| PostgreSQL database | 500 MB / project |
| Storage | 1 GB |
| Maximum individual/global Storage upload | 50 MB |
| Egress | 5 GB |
| Cached egress | 5 GB |
| Active hosted projects | 2 |
| Automatic backup | Not included |
| Inactivity | Project may pause after one week of inactivity |

## Rules

- Never hardcode these provider limits into business logic.
- Re-verify them at deployment time because provider limits can change.
- Use them only for planning budgets, System Health thresholds, and deployment validation.
- The two active hosted projects are reserved for separate `dev` and `live` environments. Local Docker does not consume a hosted-project slot.
- The 50 MB upload limit is a Package 01 design/validation input, not an application import rule.
- Because the Free plan has no automatic backup, a logical export/restore runbook and rehearsal are mandatory before the first live release in Package 00C.
