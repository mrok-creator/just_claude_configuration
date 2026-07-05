---
name: e2e-feature-verification
description: Live end-to-end verification of a backend feature through real running services and HTTP endpoints — start the service set, bootstrap auth, exercise the feature's endpoints (happy path + negative cases), assert responses. Use when asked to verify a feature works "for real" (e2e, live check) and automated e2e coverage does not exist yet. Per-service recipes live in references/.
allowed-tools: Read, Write, Edit, Grep, Glob, Bash
---

# E2E Feature Verification

Interim harness until the project has proper automated e2e coverage. General
procedure below; service-specific facts (ports, auth flow, endpoint maps,
fixtures) live in `references/<service>.md` — ALWAYS check for one first and
reuse it. After a run, fold newly discovered facts back into the reference.

## Step 0 — Reuse check

- `ls .claude/skills/e2e-feature-verification/references/` — if the target
  service has a recipe, Read it and follow it; only fall back to discovery
  (Step 2) for gaps.
- Confirm with the user which feature/endpoints are in scope and whether
  services are already running (infra — database, message broker, cache — is
  assumed up; starting it is the operator's job).

## Step 1 — Service set + startup

- Derive the minimal service set: the HTTP entry point (gateway) + the target
  service + its direct dependencies (e.g. auth flows need the authentication
  and role services; file flows need the file service). Check the reference
  first; derive from module imports/RPC clients only when the reference lacks it.
- Startup (operator terminal, not Claude): use the project's serve command
  (example for an Nx workspace: `npx nx run-many -t serve -p <set>`).
- Readiness: `lsof -iTCP -sTCP:LISTEN -P -n | grep -i node`, then
  `curl -s -o /dev/null -w "%{http_code}" http://localhost:<HTTP_PORT>/api`.
  Some services listen on TWO ports — an internal transport port (returns 400
  to HTTP; never curl it) and the real HTTP port — record which is which in
  the reference.
- Port conflict (`EADDRINUSE`): `lsof -nP -iTCP:<port> -sTCP:LISTEN` →
  `ps -p <pid> -o pid,ppid,etime,command` → `kill -15 <pid>` — inspect before
  killing; never `kill -9` first.

## Step 2 — Route/DTO discovery (once per feature)

Download Swagger once and mine it — do not guess routes or payload shapes:

```bash
curl -s http://localhost:<HTTP_PORT>/api/docs-json -o $SCR/swagger.json
jq -r '.paths | to_entries[] | .key as $p | .value | to_entries[] | "\(.key|ascii_upcase) \($p) \(.value.tags)"' $SCR/swagger.json | grep -iE "<feature>"
jq '.components.schemas.<Dto>' $SCR/swagger.json
```

## Step 3 — Auth bootstrap

- Registration may not be public (may need an admin-level token) — ask the
  operator for an admin token or an existing test user; do not try to bypass.
- A user without roles may not be able to log in — assign a role right after
  registering if the project uses role-based access.
- Persist the token to a scratchpad file (`$SCR/token.txt`) — shell state does
  NOT survive between Bash calls; re-source helpers/token at the start of
  every command block.

## Step 4 — Exercise + assert

- Happy path first, then negative cases: missing required field, bad enum,
  ghost FK (valid-format UUID that does not exist), non-UUID where UUID
  expected, no Authorization header, duplicate submission.
- Assert on: HTTP status, response DTO fields, and a follow-up GET confirming
  persistence — never on "no error" alone.
- Verification is via HTTP only — no direct dev-DB queries.
- Async/polled flows: poll the status endpoint in a bounded loop (attempts
  cap + sleep), never an unbounded `while`.

## Step 5 — Report + teardown

- Report per case: request → expected → actual → PASS/FAIL. FAILs include the
  response body.
- Clean up scratchpad secrets (`rm $SCR/token.txt`). Test data left in dev DBs
  is acceptable — use unique run-suffixes in fixture IDs so reruns don't
  collide; note the residue in the report.
- Update `references/<service>.md` with any newly discovered ports, routes,
  pitfalls, or fixtures.

## Known cross-service pitfalls

- `curl -w "HTTP_STATUS:%{http_code}"` piped into `jq` → jq exit 5. Save body
  with `-o body.json`, print status separately, run jq on the file.
- List endpoints may return a BARE array — `jq '.items[]'` fails with exit 5;
  probe shape first (`jq 'type'`).
- Filter operators may need a literal `$` (e.g. `filter=status__$eq__X`) —
  single-quote the argument or the shell eats `$eq`; use
  `curl -G --data-urlencode '...'`.
- `status` is read-only in zsh — never `local status=` in helpers; use `st`.
