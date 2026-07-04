# C: cast expression as call argument fails to parse

- **Type:** bug (C frontend / parser) — Track C
- **Status:** DONE (already fixed since v152; regression test added) — 2026-07-04

## Resolution (2026-07-04)

No longer reproduces — fixed incidentally by C-frontend work landed since v152.
Verified on current master AND pinned v171: `printf("t=%d\n", (int)t)`,
`g((int)t)`, and `printf("a=%d b=%d c=%ld\n", (int)x, (int)d(), (long)x)` all
parse and produce correct values (`t=5`, `a=7 b=3 c=7`) — both the vararg and
plain-call forms the ticket flagged. Added regression test
`test/ccast_call_arg.c` (cast as vararg + plain call arg) wired into
`make test` (expects `v=20 s=22`) so it stays fixed.
- **Opened:** 2026-07-02, found during bug-max-proc-params-32-selfmiscompile
  (verified identical on pinned v152 — pre-existing).

## Symptom

`printf("t=%d\n", (int)t);` → `error: expected C expression`. A cast as a
direct call argument does not parse; hoisting to a local (`int ti = (int)t;`)
works, and casts elsewhere (initializers, returns: `return (int)sum32(...)`)
work.

May be vararg-call-specific — check both vararg and plain calls.
