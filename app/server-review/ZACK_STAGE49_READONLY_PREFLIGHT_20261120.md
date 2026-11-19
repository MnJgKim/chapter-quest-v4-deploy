# Stage 49 — Zack Files Chapter 1 read-only production preflight (2026-11-20)

Project: ftffxetmqditfqdvzjdd. All database checks below were SELECT-only; no deployment, migration, scheduling, or student-data mutation in this stage.

## Verified in live production DB
- Shared chapter UUID: `1dcf0d1f-c048-4e3a-bb7e-3d05c4600143`; PDF ready and storage path present; published questions: 10.
- Parent approval ID `a10a754c-737e-4abc-b18d-d9a5f9e6d91d` and approval hash `5097acd14ed9a58937a2863eaab8a720`; approval request row matches both fields and parent.
- Seowoo `b7c90ec0-da6b-4519-90cb-58a07d6881a6`: schedule 2026-11-23, released_at set, assignment present, enrollment present.
- Seojin `fde16ade-a761-4aee-9992-a453f2668488`: schedule 2026-11-24, released_at set, assignment present, enrollment present.
- Zack chapter has zero submissions; no student-level submission/feedback isolation has been exercised with real JWTs.
- Seowoo other active schedules: 0. Legacy Magic Tree House Ch1 PDF/activity/submission: 1/1/1, unchanged.
- Private backup `seowoo-zack-switch-20261120` digest `03ff07516d32dada4bf112e22ab19082` verified equal to md5(payload::text), contains 10 original Seowoo schedule rows.
- Storage buckets `cq-v4-originals` and `cq-v4-speaking` have public=false.
- `cq_v4_is_released` source explicitly checks auth.uid() student or parent-admin, verified PDF, assignment, enrollment, published activity, released_at, and current date in the schedule timezone >= lesson_date.
- Existing `cq-v4-pdf-link` Edge Function ACTIVE v2, verify_jwt=true; `cq-v4-pdf-parent` ACTIVE v3. New `cq-v4-parent-preview` NOT deployed.
- Public cq_v4_* RPCs observed to deny anon EXECUTE. This is a privilege inspection, NOT a live JWT bypass test.

## Not verified / must not be marked complete
1. Real Seowoo/Seojin JWT sign-in, pre-release and release-day API access, PDF Edge signed link, and direct unauthenticated Storage GET denial.
2. Two real authenticated students submitting answers and reading only their own feedback; use safe test fixtures rather than writing to production student records.
3. Full npm test, PostgreSQL integration tests on isolated DB, GitHub Actions run ID and successful job logs.
4. Actual parent-preview Edge runtime and mobile/tablet browser rendering.
5. Cloudflare/Edge deployment and restoration rehearsal. Require explicit production deployment approval and separate backups.

## Repeatable read-only SQL
```sql
SELECT change_key, payload_md5, payload_md5=md5(payload::text) AS valid
FROM cq_v4_ops_private.schedule_change_backup
WHERE change_key='seowoo-zack-switch-20261120';

SELECT s.student_user_id,s.chapter_id,s.lesson_date,s.timezone,
       s.released_at IS NOT NULL AS release_flag,
       EXISTS(SELECT 1 FROM cq_v4_pdf_assignments a WHERE a.chapter_id=s.chapter_id AND a.student_user_id=s.student_user_id) AS assigned,
       EXISTS(SELECT 1 FROM cq_v4_pdf_enrollments e WHERE e.parent_user_id=s.parent_user_id AND e.student_user_id=s.student_user_id) AS enrolled
FROM cq_v4_lesson_schedule s
WHERE s.chapter_id='1dcf0d1f-c048-4e3a-bb7e-3d05c4600143'
AND s.student_user_id IN ('b7c90ec0-da6b-4519-90cb-58a07d6881a6','fde16ade-a761-4aee-9992-a453f2668488')
ORDER BY s.lesson_date;
```

## Safe future chapter workflow
1. Register original Zack PDF as a new immutable chapter UUID; verify parent ownership, storage path, page range and PDF digest.
2. Extract separate text for question authoring; preserve original PDF display. Generate and parent-review questions, answer key, vocabulary, writing and speaking prompts.
3. Register genuine parent approval and content hash; publish once only after exact payload match.
4. Assign same approved chapter UUID to each student; create separate student-specific schedule dates, releases and enrollment.
5. Preflight both students' read permissions; verify no pre-release access, no cross-student submissions/feedback, and retention of historical Magic Tree House records.
6. After backup, obtain separate deployment approval before any production Worker/Edge/DB changes.
