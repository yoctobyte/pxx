---
prio: 55
---

# flaky: cJSON / lua corpus runners race on a shared /tmp input path under parallel testing

- **Type:** test-harness flakiness. Track C (owns `test/cjson/**`, `test/lua/**`).
- **Found:** 2026-07-08, while resolving `regression-cfront-stmt-expr-25c1dded`.

## Problem
Both corpus runners read a single **hardcoded** input path and rely on the Makefile
copying each fixture there before running:

- `test/cjson/runner.c`  → `#define PXX_CJSON_INPUT "/tmp/pxx_cjson_input.json"`
- `test/lua/runner.c`    → `#define PXX_LUA_SCRIPT  "/tmp/pxx_lua_input.lua"`
  (comment: "C argv is not wired yet, so the Makefile copies each case to that fixed path")

The `test-cjson` / `test-lua` Makefile loops do `cp $case /tmp/pxx_..._input; run`.
Serially this is fine. Under **parallel** test execution (borg full-tier), two cases
share the one path — case B overwrites the input while case A's runner is mid-read, so
A serializes B's document. Manifested as a false wrong-output RED:
`test-cjson#00` reported `scalars.json` emitting `strings.json` content (see the parent
ticket). Not a compiler bug — a shared-mutable-file race in the harness.

## Fix options
1. Wire C argv (`main(argc, argv)`) in the runners and have the Makefile pass the
   fixture path directly — no shared temp at all. Preferred; also removes the `cp`.
2. If argv stays unavailable: make each invocation's temp path unique
   (`mktemp`, or embed `$$`/case-name), and pass it via an env var the runner reads
   with crtl `getenv`.
3. Or serialize these two suites (mark them non-parallel in testmgr). Cheapest, but
   leaves the latent footgun for any future fixed-`/tmp`-path runner.

## Gate
`make test-cjson` + `make test-lua` green, and the two suites pass when run under
`tools/testmgr.py` parallel full-tier without input-file cross-contamination.

## Log
- 2026-07-08 — resolved, commit dbdc0c2c.
