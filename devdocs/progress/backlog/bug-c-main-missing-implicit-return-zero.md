---
summary: "C: main() falling off the end returns stack garbage instead of 0 (i386)"
type: bug
track: C
prio: 65
---

# `main()` without a `return` yields a garbage exit status

- **Type:** bug (C frontend) — **Track C**
- **Found:** 2026-07-31 by Track T, triaging the c-conformance leg of
  [[regression-cascade-b45c759f9e65]].
- **Standard:** C99 §5.1.2.2.3 — reaching the `}` of `main` is equivalent to
  `return 0;`. gcc oracle agrees (exit 0).

Filed as a `bug-` rather than a `compat-c-*` ticket under the escape rule: this
is **silent wrong behavior** (a wrong exit status a caller acts on), not a
diagnostic-parity nicety.

## Repro (measured, not inferred)

`library_candidates/c-testsuite/tests/single-exec/00211.c` — 12 lines, `main`
ends without a `return`:

```c
extern int printf(const char *format, ...);
#define n 0xe
int main()
{
    printf("n+1 = %d\n", n+1);
}
```

Minimal pair, both built with `pascal26 --target=i386`, same binary run three
times each:

| source | run 1 | run 2 | run 3 |
|---|---|---|---|
| `main(){ printf("x\n"); return 0; }` | 0 | 0 | 0 |
| `main(){ printf("x\n"); }`           | **220** | **172** | **188** |

gcc on the same file: exit 0. `pascal26` x86-64 and arm32: exit 0 — **by luck**,
the return register happens to hold 0 there, which is why this hid for so long.

## Layer

The frontend, not the backend. Adding an explicit `return 0` makes i386 exit 0
deterministically, so the i386 return-value path is sound; nothing supplies the
implicit zero when the function body simply ends. Fix belongs wherever C
function bodies are lowered — apply it for `main` specifically (C99 exempts only
`main`; any other non-void function falling off the end stays undefined and
should keep whatever diagnostic it has today).

## Why it matters beyond one test

This is the `test-c-conformance-i386#shard0/6` red that has been carried in
tstate all day, and it is **nondeterministic**: `00211.c` has reported
`exit=188`, `exit=140`, `exit=76` across three consecutive full runs
(reports `20260731T131923Z-b45c759`, `20260731T155147Z-78847f9`,
`20260731T162036Z-6104264`), plus 220/172/188 locally. A red whose failure
signature changes every run is the kind that gets dismissed as flake — it isn't;
it's a real bug that reads garbage.

## Triage note for the cascade ticket

[[regression-cascade-b45c759f9e65]] says "treat as ONE root cause until triage
proves otherwise; do NOT fan out per-job tickets." Triage has now proved
otherwise for this leg: the c-conformance shards are a genuine, reproducible
frontend bug and are **separable** from the rest of that cascade
(`test-sqlite-threads-*`, `test-lua-cross`), which remain unexplained. Splitting
this one out is deliberate, not a violation of that instruction.
