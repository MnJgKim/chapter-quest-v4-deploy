# Verified PDF range candidate — NOT applied to production

This change fixes a selected-page lesson being connected to the complete original through the parent PDF dropdown. The frontend requires the exact server-verified derived UUID. The server independently extracts the selected pages from the parent's owned verified original, records source/derived SHA-256 and actual page count, and atomically binds approval to that derived UUID. Retrying the same request reuses it; conflicting bounds are rejected. The source is downloaded inside the server, never uploaded again or overwritten. Existing local TXT and previously registered files remain intact.

Proposed scope for a future separately approved operation:

- Add only `20261111233341_cq_verified_pdf_ranges.sql`: one private range registry, one service-only commit RPC and one parent-only approval RPC. RLS is enabled, browser roles have no direct registry access, and both functions pin an empty search path. Do not apply the local bootstrap schema to production.
- Replace the reviewed `cq-v4-pdf-parent` and `cq-v4-pdf-link` candidates, including `_shared/pdf-range.ts`, keeping JWT verification enabled. Parent preview remains admin/owner-only. Student links require current assignment/enrollment, a published lesson, correct approval ownership and an exact derived-file hash. Missing registry/authorization checks fail closed. No Storage policy is broadened.
- Deploy the separately reviewed frontend only after server compatibility is checked. The viewer checks the verified page count before exposing the PDF or enabling submission.

None of these production changes has been authorized or executed. Creating a range later adds one derived object and chapter plus registry row; publishing/assigning writes lesson records. These operations need explicit approval on the operating project. No paid resource is needed for development testing. Actual 29.3MB extraction time/memory within the operating free Edge limits remains unverified; a deployment approval is not a claim of guaranteed runtime capacity.

Before any approved change: capture current function source/JWT config, schema/function definitions, private object metadata and table fingerprints, and verify the exact reviewed commit. The parent preview/download action itself performs no writes. First inspect the actual original and choose file-page bounds manually; Chapter 1's bounds are unknown and must remain blank until confirmed.

Rollback: restore the immediately preceding frontend and both captured Edge versions together, preserving JWT settings, existing data, range registry, derived objects and all student submissions. Keep additive SQL in place rather than dropping referenced data. A code rollback does not erase approved assignments or revoke already issued links (120-second lifetime); any subsequent data correction or access revocation requires a separate reviewed operation. Do not delete the original, anonymous user, existing links or derived records as a rollback shortcut.

Tests distinguish local synthetic Auth/Storage/Edge runs, HTTP-mocked browsers, isolated PostgreSQL and physical-device checks. Real operating PDF contents, anonymous-account recovery, actual AI quality and Galaxy hardware remain outside those automated results.


## Latest full-original range exception (candidate only)

The user confirmed the 11-page Chapter PDF and selected file pages 1–11 including covers, contents and illustrations. For a complete range only, the candidate reuses the exact original UUID/bytes with no upload, replacement, duplicate object/chapter or deletion. Source and target hashes must match and bounds must be 1..actual total. A new range registry record is still an operating write and remains unapproved. Partial ranges still require a distinct derived file. Student approval/assignment/enrollment/integrity checks remain mandatory. Earlier statements requiring a distinct UUID for every range apply to partial ranges; the unmodified original is now allowed for a verified complete range. The helper/Edge/SQL changes must be reviewed together. Older student Edge code rejects this new whole-original manifest, so rollback compatibility must be checked before restoring prior versions.
