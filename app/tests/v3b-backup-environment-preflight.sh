#!/usr/bin/env bash
# Read-only local capability check; no credentials, no remote database access.
set -u
printf 'Chapter Quest V4 backup environment preflight\n'
printf 'Repository: '; git remote get-url origin 2>/dev/null | sed -E 's#(https?://)[^/@]+@#\1[REDACTED]@#' | sed -E 's#git@github.com:#github.com/#' || echo unavailable
printf 'Git branch: '; git branch --show-current 2>/dev/null || echo unavailable
for command in docker supabase psql pg_dump node; do
  if command -v "$command" >/dev/null 2>&1; then printf '%s: available\n' "$command"; else printf '%s: missing\n' "$command"; fi
done
if command -v docker >/dev/null 2>&1; then
  if docker info >/dev/null 2>&1; then echo 'Docker daemon: available'; else echo 'Docker daemon: unavailable'; fi
fi
printf 'Free disk space: '; df -h . | awk 'NR==2{print $4}'
printf 'Safe preflight complete. No secrets requested or read.\n'
