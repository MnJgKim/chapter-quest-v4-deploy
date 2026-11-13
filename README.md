# Chapter Quest V4

P0 server-contract development branch. The original deployment ZIP is preserved;
`public/` and `wrangler.jsonc` contain its extracted app plus targeted P0 changes.

Read [the P0 contract](docs/P0-CONTRACT.md) and [AI/TXT/session continuation](docs/P0-AI-TEXT-SESSIONS.md) before setup.

```sh
npm ci
npm run check
npm test
```

Tests use isolated PGlite PostgreSQL and disposable Chromium sessions with mocked
external HTTP. They never use production credentials or modify remote data.
SQL migrations are a baseline for a **new local/test Supabase project only**.
No production or Cloudflare deployment has been performed. Student final-submit UI
remains disabled until full test-project integration has passed.
