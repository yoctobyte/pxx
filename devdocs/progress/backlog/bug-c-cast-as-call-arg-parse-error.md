# C: cast expression as call argument fails to parse

- **Type:** bug (C frontend / parser) — Track C
- **Status:** backlog
- **Opened:** 2026-07-02, found during bug-max-proc-params-32-selfmiscompile
  (verified identical on pinned v152 — pre-existing).

## Symptom

`printf("t=%d\n", (int)t);` → `error: expected C expression`. A cast as a
direct call argument does not parse; hoisting to a local (`int ti = (int)t;`)
works, and casts elsewhere (initializers, returns: `return (int)sum32(...)`)
work.

May be vararg-call-specific — check both vararg and plain calls.
