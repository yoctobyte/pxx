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

## Expectation — DECIDED 2026-07-02 (user): stay include-compatible

The include-driven crtl link model stays (printf lives in `<stdio.h>`; the
include is what pulls the impl — devdocs/dev/c-linking-and-crtl-autopull.md).
Do NOT auto-bind bare printf to the crtl impl. Standard-C context: hosted C
requires `<stdio.h>` for printf anyway (implicit declaration is UB since
C99), so "no include ⇒ no real console printf" matches real compilers; the
literal-only stub below is a pxx courtesy BEYOND the standard, kept so a
dependency-free hello still prints.

REFINED 2026-07-02 (user): reject ALL unresolved printf — no courtesy stub.
C is multiplatform/minimal; assuming a std output without stdio is already
an assumption, and our C is stable enough that test apps can be required to
include stdio. The literal-only stub is a relic of early C bring-up days.

1. **Explicit prototype, no include** (`int printf(const char*, ...);`):
   currently a body-less extern — call silently swallowed. COMPILE ERROR:
   "printf declared but has no implementation — `#include <stdio.h>`
   (bundled libc-free impl) or `--system-libs`".
2. **No include, no prototype**: DELETE the `ParseCPrintfAST` literal-only
   stub (cparser.inc ~2069 + its dispatch guard ~2939) outright. Bare
   printf without a resolvable impl = same compile error as (1).
3. `--system-libs`/`--system-libs=c` path unchanged (real libc printf).

Result: every printf either formats correctly or fails loudly at compile
time; nothing prints wrong output silently.

Gate fallout to fix in the same change (tests that lean on the bare stub —
add `#include <stdio.h>` and, where output was the raw format string,
correct the expected output): `test/hello.c` (in `make test`, expected
"Hello, World!" keeps working via the include), `test/macro_soup_lib.c`,
`test/csqlite_layout_probe.c`, `test/csqlite_schema_exec_probe.c`. The
cvararg gate tests already `#include "stdio.c"` and are unaffected.
