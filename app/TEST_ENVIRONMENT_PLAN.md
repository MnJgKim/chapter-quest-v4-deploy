# Zero-additional-cost test and release plan

Paid Supabase branches, paid services, plan upgrades and paid AI usage are not authorized. Do not create them. Existing production users, sessions and student data must not be changed without separate user approval.

## Completed local path

- The organization `우진화이또` is on Supabase Free. The account lists one active and one inactive project. Official billing documentation allows two active Free projects and excludes paused projects. This suggests a spare free slot, but actual eligibility has not been tested by creating a project; no hosted test project is needed for the current local work.
- Docker is available. The full local CLI stack failed at the execution environment's disk limit; the lean local setup successfully runs real Auth, PostgreSQL and PostgREST. All new users/fixtures are local only. See `local-supabase/README.md` for precise coverage and limits.
- Parent/student browser mocks cover complete PDF/audio submission and recovery. Real local Auth/REST browser tests additionally verify account isolation and persisted feedback.

## Free lesson preparation

Use parent-authored questions/model answers or import a validated JSON lesson draft into the parent review screen. This makes no AI API request and requires explicit parent review and approval. Existing ChatGPT Plus can be used interactively to prepare a JSON draft; a Plus subscription does not supply an API credential to this application.

The Cloudflare AI route defaults to disabled (`AI_FREE_PLAN_CONFIRMED=false`). Before enabling it, verify that the target account is on Workers Free, that the model is available, and that account-wide AI usage remains within the published 10,000-neuron/day free allocation. Never upgrade the plan or silently enable paid inference. On Workers Free, requests beyond the free allocation fail instead of being billed. Account-wide usage by other apps must also be considered. Source: https://developers.cloudflare.com/workers-ai/platform/pricing/ .

## Remaining gates

1. Confirm the correct Cloudflare account and its free plan through a secure authenticated connection. Do not request tokens/passwords in chat. Keep AI disabled until that check is complete.
2. If hosted integration is still needed, first recheck Free project eligibility. Any project creation must remain explicitly Free, contain only new synthetic identities/data and must not replace, restore, pause or modify an existing project. Stop if free eligibility cannot be established; never substitute a paid resource.
3. Check actual hosted PDF/recording behavior and the intended student device before declaring the cross-device flow production ready. Local tests do not prove hosted Storage/Edge parity.
4. Prepare the actual first lesson for 2026-11-23, verify student assignment and obtain explicit user approval before production deployment or production data changes. Record the immediately preceding deployment and rollback steps before approval.
