# Per-service e2e recipes

This directory accumulates one recipe file per service, written and updated by
the `e2e-feature-verification` skill itself.

Each `references/<service>.md` captures the service-specific facts discovered
during live verification runs, so the next run does not have to rediscover them:

- HTTP port(s) and any internal transport ports (which one to curl, which never)
- Auth bootstrap flow (how to obtain a token, test users, role requirements)
- Endpoint map for verified features (routes, DTO shapes, filter syntax)
- Fixtures and unique-suffix conventions for test data
- Service-specific pitfalls hit during runs

The directory starts empty on a fresh install. After every verification run,
fold newly discovered facts back into the target service's recipe file (create
it if missing).
