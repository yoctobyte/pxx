# C `static` local with an initializer re-runs the initializer every call

- **Type:** bug
- **Track:** A/C — cfront lowering of block-scope `static` locals
  (`compiler/cparser.inc` ~2826, `CLocalStaticDecl`)
- **Status:** backlog
- **Opened:** 2026-07-02
- **Found while:** Track B probing untested C-frontend surface (no existing
  test covers static-local + initializer state across calls).

## Repro

```c
#include <stdio.h>

int counter(void) {
    static int n = 10;
    n = n + 1;
    return n;
}

int main(void) {
    printf("%d\n", counter());
    printf("%d\n", counter());
    printf("%d\n", counter());
    return 0;
}
```

Expected (and what real C / this project's own x86-64 output should be):
```
11
12
13
```

Actual:
```
11
11
11
```

**Without an explicit initializer** (`static int n;`, relying on implicit
zero-init) the same pattern works correctly — `n = n + 1` across 3 calls
correctly prints `1 2 3`. So the storage itself *does* persist (BSS, per the
`cparser.inc:2826` comment about pointer survival for sqlite's static vfs
table) — only the **explicit initializer** is the problem: `static int n = 10;`
is being lowered as an assignment statement that runs on every function entry,
not a one-time load-time initializer.

## Why it matters

`static` locals with initializers are an extremely ordinary, common C pattern
(counters, lazily-initialized caches, "have I warned about this once" flags,
`static const` lookup tables assigned via a runtime expression). Currently
**any** state seeded through a static-local initializer is silently reset to
its initial value on every call — this is a silent-wrong-behavior bug, not a
compile error, so it will not be caught by "does it compile" checks; it needs
an actual runtime comparison to notice (as this probe did).

## Suggested investigation

`CLocalStaticDecl` (`cparser.inc:2826`) routes through the normal
`ParseCLocalDeclAST` path with the flag set to move storage to BSS/global, but
the initializer expression is still emitted inline in the function body (as
for a normal auto local) instead of being hoisted to a load-time/global
initializer that runs exactly once. Fix likely needs the static-local's
initializer to be treated the same way a global variable's initializer is
(one-time, at program start), gated so it doesn't re-run per call — while
still allowing the *non-initialized* case (implicit zero, which already works)
to fall through unchanged.

## Acceptance

- The repro above prints `11 12 13`.
- A static local with a non-constant/computed initializer (e.g.
  `static int n = SomeGlobal + 1;`) still only evaluates that expression once.
- Existing static-local behavior (implicit zero-init, pointer survival for
  sqlite's static vfs table) stays green.

## Log
- 2026-07-02 — Filed by Track B. Isolated via 3 minimal repros (no-initializer
  works, zero-initializer masked the bug by coincidence, non-zero initializer
  exposes it cleanly). No code touched — test/repro only.
- 2026-07-02 — Track A: fixed. ParseCLocalDeclAST now wraps a static-local's
  initializer chain in a one-time guard (`if guard == 0 { guard = 1; inits }`,
  hidden BSS int guard, CWrapStaticInitOnce) at both block-build sites (incl.
  the inline fn-ptr declarator early exit). Repro prints 11 12 13; new gate
  test/cstatic_local_init_once_b139.c covers computed initializers, implicit
  zero, multi-declarator lines. make test + test-lua green, self-host
  byte-identical.
