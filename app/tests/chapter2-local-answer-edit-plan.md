# Chapter 2: edit only MC #7 in local parent editor, preserve ten questions

## Verified UI behavior
- `app/public/js/local-app.js`: `챕터 관리 → 편집 / AI 문제 생성 → 저장된 문제·정답·근거 수정` loads current LOCAL `c.questions` into `draft`.
- MC correct option is an integer zero-based `q.correct`, edited with `data-review-field="correct"`.
- Local parent approval updates `c.questions` and local-only `approvalReceipt`; it does not update server activity.
- `app/public/js/parent-app.js` `publicationPayload` sends each non-MC `sample` as a STRING in `answerKey`, **not null**. Previous proposed server payload `[1,3,0,1,1,0,1,null,null,null]` is NOT compatible with the existing parent publish client and requires correction.
- Current server publish path invokes `cq_v4_bind_verified_pdf` then `cq_v4_publish_approved`; neither is a safe in-place edit path for an already approved published chapter.

## Recommendation
1. Before any editing, back up local data; ensure LOCAL Chapter 2 has exactly 10 questions (7 MC, 2 short, 1 inference) in the right order. Local storage is not guaranteed to match server.
2. Use '저장된 문제·정답·근거 수정', adjust only #7 correct choice to Red (index 1), and review evidence.
3. Save local parent approval; this is NOT a server correction.
4. A new server approval request must use all ten unchanged questions, the corrected #7 index and non-MC sample strings. Integrate a dedicated safe in-place republish RPC (existing dev replacement RPC currently requires null non-MC keys and must be adapted to actual registration contract).
5. Test PostgreSQL and student UI before requesting separate production authorization.
6. Do not use six-question restore RPC or standard '승인 자료 게시' button for the existing published Chapter 2.

No production writes authorized.
