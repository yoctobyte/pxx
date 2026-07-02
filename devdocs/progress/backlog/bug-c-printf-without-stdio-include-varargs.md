# C: printf without #include <stdio.h> silently drops output / formatting

- **Type:** bug (C frontend / crtl binding) — Track C
- **Status:** backlog
- **Opened:** 2026-07-02, found during bug-max-proc-params-32-selfmiscompile
  (verified identical on pinned v152 — pre-existing).

## Symptom

Without `#include <stdio.h>`:
- Implicit `printf("x=%d\n", x)` prints the format string LITERALLY
  (`x=%d`) — varargs ignored (bare `printf("hello\n")` works: test/hello.c).
- With an explicit prototype `int printf(const char *fmt, ...);` there is NO
  output at all — the call is silently swallowed (exit code fine).

With `#include <stdio.h>` everything formats correctly (crtl auto-pull).

## Repro

    int printf(const char *fmt, ...);
    int main(void){ printf("hello\n"); return 7; }   /* no output, exit 7 */

    int main(void){ int x=42; printf("x=%d\n", x); return 0; }  /* prints x=%d */

## Expectation

Either bind the no-include printf to the same crtl impl (C89 implicit-decl
behaviour), or make it a clear compile error — not silent wrong output.
