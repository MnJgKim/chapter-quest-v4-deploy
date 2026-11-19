# 2026-11-20: Shared Zack Files lessons for Seowoo + Seojin (deployment preflight)

User-selected policy: for roughly one month, Seowoo studies the same Zack Files PDF and approved questions as Seojin; Magic Tree House #2 resumes **after** Zack Files is finished. Preserve all Magic Tree House PDFs, activities, approvals, historical submissions, and snapshots. No deletion required.

## Read-only production evidence
- Seowoo user `b7c90ec0-da6b-4519-90cb-58a07d6881a6` has Magic Tree House #2 Chapter 1–10 scheduled Nov 23–Dec 14.
- Seojin user `fde16ade-a761-4aee-9992-a453f2668488` has Zack Files Chapter 1 `1dcf0d1f-c048-4e3a-bb7e-3d05c4600143` scheduled Nov 24. The PDF is verified, activity published, and approval ID bound.
- Lesson schedule key is `(student_user_id,chapter_id)`, so both students may have separate schedules for the **same chapter UUID**. Assignment key is `(chapter_id,student_user_id)`; submissions are keyed by student. This permits shared content without copying/overwriting questions.
- **Only Zack Chapter 1 is verified ready**. Do not create future chapter assignments until the approved content and PDFs exist.

## Production change proposed, NOT yet applied
1. Back up the exact rows of `cq_v4_lesson_schedule`, `cq_v4_pdf_assignments`, `cq_v4_pdf_enrollments`, and `cq_v4_activities` for both students, plus a restorable schema/database backup.
2. Verify the Zack Chapter 1 owner is the same parent, student enrollment exists, activity approval is bound, PDF ready, and no Seowoo submission for that Zack chapter exists.
3. Add Seowoo assignment to Zack Chapter 1; schedule it for **2026-11-23** (Monday), retaining Seojin's **2026-11-24** (Tuesday). Do not change Seojin's records.
4. The existing Seowoo Magic Tree House Nov 23–Dec 14 schedule must be **deactivated/removed from active schedule** to avoid duplicate daily lessons; preserve a complete reversible row backup. Keep original PDF and activity untouched.
5. **Important:** `cq_v4_lesson_schedule` has no `status`/pause flag. Changing or removing active rows is a production schedule mutation. It must be explicitly authorized after backup and restore plan. Do not merely move them to arbitrary future dates: actual Zack completion date is unknown.
6. Future Zack chapters: one shared approved chapter, two independent student assignments, independent lesson dates (Seowoo Mon/Wed/Thu, Seojin Tue/Wed/Fri), independent submissions and feedback. Resume Magic Tree House after Zack completion with new schedule dates.
7. Run the actual student-authorized `cq_v4_is_released` and signed PDF-link tests, ensure no pre-date leakage. Verify separately on both accounts.

## Required explicit production approval
Ask user to approve the precise schedule mutation: archive existing Seowoo Magic Tree House active schedule rows (reversible backup, no PDF or activity deletion) and assign Zack Chapter 1 to Seowoo for Nov 23, while preserving Seojin's Nov 24 date. No change before the backup is verified.
