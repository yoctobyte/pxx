---
prio: 90  # auto
---

# C: hand-declared libc prototypes (no #include) silently no-op in libc-free mode

- **Type:** bug/feature (cfront crtl binding). Track C.
- **Priority:** HIGH — `extern int printf(const char*, ...);` COMPILES, LINKS,
  and the call silently does NOTHING (no output, no error). Classic C89 style,
  c-testsuite uses it throughout; real code will too.
- **Found:** 2026-07-06 c-testsuite run.

## Failing tests
- 00210 (also parses `__attribute__((packed/stdcall))` — that part works)
- 00211, 00215, 00217 — all declare printf by hand, output empty.

## Why
crtl impl auto-pull is keyed on the `#include <hdr>` path; a bare prototype is
marked external-against-libc, and a libc-free link leaves it unbound → call is
a silent nop. Either bind it or make it a HARD link error — silence is the bug.

## Prior art (reverted 2026-07-06 — landed without ticket/review, pulled back out)
Previous session drafted in cparser.inc: after pass 1, scan procs still
ProcExternal whose name is a known crtl libc symbol (table name→header for
stdio/stdlib/string/ctype/math), synthesize the `#include` lines, CPreprocess +
CLexAppend them, and run the appended region through the pass-1 loop before
pass 2 compiles bodies; no-op under --system-libs. Approach worked (took suite
178/220) but needs proper review: table duplication vs crtl manifest, pass-1
re-entry, interaction with CHeaderMode. Rebuild it deliberately from this
ticket.

## Gate
Drop 00210/00211/00215/00217 from test/c-conformance/pxx.skip; runner green;
make test + self-host byte-identical.

## Log
- 2026-07-07 — resolved, commit 147087b0.
