# Production switch — Seowoo to shared Zack Files Chapter 1

Approved by parent and applied 2026-11-20 KST. Supabase project `ftffxetmqditfqdvzjdd`.

- Parent: `967982a4-19f9-4a32-a2d5-976f4569091f`
- Seowoo: `b7c90ec0-da6b-4519-90cb-58a07d6881a6`
- Seojin: `fde16ade-a761-4aee-9992-a453f2668488`
- Shared Zack chapter: `1dcf0d1f-c048-4e3a-bb7e-3d05c4600143`
- Private backup: `cq_v4_ops_private.schedule_change_backup`, key `seowoo-zack-switch-20261120`, MD5 `03ff07516d32dada4bf112e22ab19082`; 10 Seowoo and 1 Seojin original schedule rows, Zack assignment and activity, enrollment.
- Applied: removed 10 Seowoo *active schedule* rows (NOT PDFs, activities, submissions, snapshots), added Zack assignment and Nov 23 schedule. Seojin Nov 24 untouched.
- Postflight: backup valid=1, Seowoo Zack schedule=1, Seojin schedule=1, Seowoo Zack assignment=1, old active=0, old Magic Tree House Chapter 1 PDF/activity/submission counts each 1.

## Recovery — only if explicitly authorized
Do not execute blindly. First verify current rows are unchanged since this switch, that Seowoo has not submitted Zack, and that no later lessons have been scheduled. In a single transaction, lock the backup row and schedules, delete only the *exact* Seowoo Zack schedule and assignment created by this switch, then restore original 10 rows from `jsonb_to_recordset(payload->'seowoo_schedule')` with original columns and timestamps. Verify row counts and digest before COMMIT. If any check fails, ROLLBACK and investigate. Never touch Seojin's schedule or original PDF/activity/submission/snapshot records.

### Read-only verification
```sql
SELECT change_key, captured_at, payload_md5,
       payload_md5=md5(payload::text) AS valid,
       jsonb_array_length(payload->'seowoo_schedule') AS original_seowoo_count
FROM cq_v4_ops_private.schedule_change_backup
WHERE change_key='seowoo-zack-switch-20261120';
```

## Remaining validation
Real student sign-in, Edge PDF link, direct Storage denial, RPC/RLS authorization, submission and feedback, and full CI tests have **not** been proven by this schedule transaction. `cq_v4_is_released` source still gates by Seoul local lesson date and authenticated student/parent authorization.
