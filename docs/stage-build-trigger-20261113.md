# Stage build trigger — 2026-11-13

This documentation-only commit triggers the Cloudflare Workers Builds integration configured for the `work/v4-safe-integration-20261113` branch.

Expected build command: `npm run build` (repository root).
Expected deploy command: `npx wrangler deploy --name chapter-quest-v4-stage`.

Safety: do not merge into `main` or deploy to the production worker `chapter-quest-v4` as part of this verification. Verify deployment logs and actual student functionality before marking stage complete.
