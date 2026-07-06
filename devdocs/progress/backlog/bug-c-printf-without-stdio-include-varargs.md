---
prio: 70  # auto
---

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

## UPDATE 2026-07-04 — mechanism moved since v152; planned fix is now dead code

Attempted the decided fix (delete `ParseCPrintfAST` stub + error on
`FindProc('printf') < 0`) and found it's a **no-op today**: the stub path is
DEAD. `FindProc('printf')` is now **>= 0 even with no include and no
prototype** — printf auto-resolves via a *different* path than the
`ParseCPrintfAST` (`FindProc<0`) stub this ticket targeted (some implicit
declaration / default proc introduced by C-frontend work since v152). Deleting
the stub + erroring on `FindProc<0` changes nothing observable — the branch is
never taken.

Current live behavior (re-verified on master 2026-07-04):
- bare / no-prototype `printf("hello\n")` → prints `hello` (string prints,
  varargs DROPPED); `printf("x=%d\n", x)` → prints `x=%d` (literal, vararg
  ignored). So a literal-only write still happens, but NOT via `ParseCPrintfAST`.
- explicit prototype `int printf(const char*,...);` no include → **no output**,
  silent swallow (unchanged from the ticket).

So the real fix must first locate WHERE printf now auto-resolves (the implicit
proc / default binding that produces the literal-only, vararg-dropping write and
the silent-swallow extern), then reject/redirect THAT — not the long-dead
`ParseCPrintfAST` stub. This is deeper than the original plan; re-scope before
picking up. Not low-hanging.

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

## Update 2026-07-07 — symptom 2 FIXED
Symptom 2 (explicit hand prototype `int printf(const char*,...)` → no output) is
FIXED by feature-c-crtl-bind-hand-declared-prototypes (commit 147087b0): a
hand-declared crtl prototype now auto-pulls the crtl impl. Verified `int
printf(const char*,...); printf("x=%d\n",5)` prints `x=5`.
Symptom 1 (IMPLICIT printf, no declaration at all) STILL prints the format
literally (`x=%d`): an implicit C89 declaration gives printf a non-variadic
int() signature, so the varargs are dropped at the call site. Remaining work =
when an undeclared call names a known crtl function, bind the correct (variadic)
crtl prototype at the call site, not an implicit int(). Separate fix.
