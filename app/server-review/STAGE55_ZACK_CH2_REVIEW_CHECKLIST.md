# Stage 55 — Zack Files Chapter 2 parent review (DRAFT)

Source: user-supplied `29-2.pdf`, 8 scanned pages, printed book pages 8–15; SHA-256 `d5a6bdc34a9bad4096678ff108c3074d52d3c041d2f44b2e75dd79b39a991f78`.

**Not parent-approved, not uploaded, not published, not assigned.** Preserve original PDF unchanged. The scan has no extractable text layer; do not represent a paraphrased study summary as a verbatim extraction.

## Verified story anchors
- p8–9: Zack and Spencer return near 4 p.m.; Dad's refrigerator has spoiled food; museum astronaut food is tried.
- p10: freeze-dried pizza tastes like cardboard; strawberry ice cream like soap; Zack discovers `spores` rather than `s'mores`.
- p11–12: Spencer explains spore survival; Zack corrects Mariner probe claim; spores hiss when water is added.
- p13–14: spore blobs grow and spread; refrigerator food disappears.
- p15: spores enter Zack's keyboard; computer displays a demand for food.

## Required parent checks
1. Review 10 original multiple-choice questions against printed pages 8–15 and confirm the answer key; check vocabulary and writing/speaking prompts.
2. Upload the **unchanged** Chapter 2 PDF through the parent UI. Keep original source text separately from the AI study paraphrase.
3. Create a genuine parent approval through the existing server flow; do not invent historic approvals.
4. Publish only after server-side approval hash and PDF ownership verification; assign only to the intended student(s).
5. Test using V4 TEST without copying test submissions to real students.

## Deployment gates
Recurring queue RPCs and scheduler are still absent from production per Stage 54. Do not enable queue actions with stub functions. Implement and test the full schema/RPC/scheduler transaction in development, including authenticated parent checks, RLS, idempotence, timezone boundaries, concurrent execution and rollback. No production DB writes or Cloudflare deployment without separate explicit approval.
