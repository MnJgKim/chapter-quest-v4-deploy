# Hosted integration gate — 2026-11-17

This is a preparation branch, **not a deployment candidate**. No production SQL, Worker, Stage Worker, Auth, Storage or student data was changed.

## Verified locally
- `node --test app/hosted-contract.test.mjs`: 5 new tests passed.
- Offline contract checks required object names and student weekday configuration. It deliberately reports `hostedReady=false` and `safeToDeploy=false` even when all names exist.
- Existing 44 feature / 11 isolation / 7 defense-regression checks were not rerun.

## First lesson release requirements (Asia/Seoul)
- Seowoo: 2026-11-23 (Monday), then Monday/Wednesday/Thursday.
- Seojin: 2026-11-24 (Tuesday), then Tuesday/Wednesday/Friday.
- Student weekday defaults exist in `app/public/js/local-app.js`, but they are local/demo planning only.
- Hosted release depends on persisted `cq_v4_lesson_schedule.lesson_date`, enrollment, assignment, PDF readiness, published activity and `released_at`. No recurring hosted assignment scheduler has been verified or implemented by this branch.
- Never assume a local weekday setting schedules a hosted lesson. Explicit parent-approved server assignments/dates are required before the first lessons.

## Cloud and feature gates
1. Compare the **actual hosted** RPC signatures, RLS grants, Storage policies and Edge versions read-only; object names alone are insufficient.
2. Check Stage Cloudflare Workers Builds failure `5cc9a368-6689-49c8-aa82-a2399f107a8f` from authenticated dashboard logs. Do not infer the failure from Wrangler names.
3. AI generation code exists in `app/worker.mjs` but real inference requires confirmed Workers Free usage, AI binding, parent Auth and `AI_FREE_PLAN_CONFIRMED=true`. Do not enable or invoke it without verification.
4. Recording needs real Galaxy mic permission, Blob encoding, Storage upload and playback verification; the lean local Auth stack does not provide hosted Storage/Edge.
5. Before any deployment, capture current Worker deployment ID, routes, vars/bindings and verified rollback access, then request explicit final approval.

## Safe execution
```sh
node --test app/hosted-contract.test.mjs
```
This test uses no network, secrets, migrations, live student accounts, or Cloudflare resources.
