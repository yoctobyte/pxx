---
summary: "cfront: __pxx_fegetround unresolved at runtime for any float-printf C program"
type: bug
track: C
prio: 55
---

# cfront: `__pxx_fegetround` unresolved on any float-`printf`

- **Type:** bug (C frontend / crtl link ordering) — **Track C**
- **Status:** backlog
- **Found / Opened:** 2026-07-25 — surfaced while checking whether
  AndreRenaud/pdfgen compiles under cfront (songformatter PDF backend probe,
  [[feature-demo-songformatter-pxx-target]]). A demanding consumer found a
  broad bug — see [[frank2-demanding-consumers-find-compiler-bugs]].

## Symptom

Any C program that prints a float via crtl's formatter fails at **runtime** with:

```
symbol lookup error: <bin>: undefined symbol: __pxx_fegetround
```

Minimal repro (3 lines):

```c
#include <stdio.h>
int main(void){ printf("%.2f\n", 1.5); return 0; }
```

```
compiler/pascal26 fmin.c /tmp/fmin   # compiles ok
/tmp/fmin                            # -> undefined symbol: __pxx_fegetround  (exit 127)
```

The produced ELF is dynamically linked (`ldd` shows libc.so.6) and the
`__pxx_fegetround` reference goes out through the dynamic PLT — but it is a pxx
intrinsic name, not a libc symbol, so nothing resolves it.

## Root cause (located, not yet fixed)

- crtl's float formatter references `__pxx_fegetround` (`lib/crtl/src/stdio.c:202-204`,
  declared extern in `lib/crtl/include/fenv.h:15`).
- cfront DOES emit the fenv stub bodies (`EmitCFenvStubs`, `compiler/cparser.inc:7152`,
  called unconditionally in the C-program path at `cparser.inc:7672`).
- But crtl `stdio.c` is auto-pulled as a C **unit** and parsed BEFORE the
  program-path stub registers `__pxx_fegetround` as a bodied proc, so its extern
  reference binds external+dynamic (`cparser.inc:8098-8100`) instead of to the
  internal body. Link-ordering / proc-registration bug.

## FIRST STEP — confirm scope on latest master

The tested `compiler/pascal26` was dated **Jul 15**; HEAD has newer `cparser.inc`
commits. Rebuild current master and re-run the 3-line repro before fixing. If it
does NOT reproduce on latest, downgrade/close. If corpus tests (zlib/quickjs)
pass while this fails, find WHY they differ (their link path vs the auto-pull
path) — that difference is the fix hint.

## Also noticed (fold in or split)

`M_SQRT2` (and likely other `<math.h>` constants) missing from crtl — pdfgen
warned `undeclared identifier 'M_SQRT2' used as value (treated as 0)`. Add the
standard math constants to `lib/crtl/include/math.h`.

## Acceptance

- The 3-line float-`printf` repro compiles AND runs, printing `1.50`.
- A crtl-float regression test (`printf("%.2f")` / `snprintf` of a double) in the
  C test corpus, wired into `make test` (or the cfront tier).
- `M_SQRT2` resolves without warning.

## Relation

Blocks the pdfgen backend (pdfgen's arc math + any float output) →
[[feature-reportlab-mimic-over-pdfgen]] → [[feature-demo-songformatter-pxx-target]].
NOT the same as [[feature-float-exception-mask-control]] (that is FPC-style float
EXCEPTION masking for the Pascal runtime; this is a cfront symbol-resolution bug).

## Log
- 2026-07-25 — filed. Root cause located, repro minimized, awaiting latest-master
  confirmation + fix.
