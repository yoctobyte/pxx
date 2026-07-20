---
prio: 10  # standing collector: rank the batch you file, not this
---

# crtl: implement the libc assumptions real-world C leans on

- **Type:** feature (libraries) — Track B (`lib/crtl`).
- **Status:** backlog, ongoing collector — 2026-07-06.
- **Premise (user, 2026-07-06):** gcc has its own libc; we have our own
  (`lib/crtl`, libc-free). Real C leans on a *waspnest of libc assumptions* —
  headers, macros, feature-test knobs, struct layouts, function contracts. Bring
  our crtl up to those assumptions incrementally, driven by what real projects
  actually touch. Don't chase completeness for its own sake — implement what the
  corpus (zlib → tcc → …) demands, one landed piece at a time.

## Why a standing ticket
Each real-world bring-up ([[feature-c-corpus-zlib]], tcc next) surfaces a fresh
batch of "libc assumed X" gaps. Rather than a ticket per tiny gap, collect them
here; split a dedicated ticket out only when a gap is large or blocks a whole
project. Distinguish: a **compiler/parser** gap is Track C (own ticket); a
**library surface** gap (missing header symbol, wrong macro, absent function) is
this ticket / Track B.

## Known / expected assumption classes (fill in as found)
- Header symbols declared-but-unimplemented (functions real code calls).
- Feature-test macros & config (`STDC`, `_LARGEFILE64_SOURCE`, `Z_HAVE_UNISTD_H`
  style probes) that gate which code path a project compiles.
- Struct layouts C code reaches into (stat, FILE internals, off_t width).
- `<limits.h>` / `<stdint.h>` / `<inttypes.h>` completeness (widths, INT*_MAX,
  format-length macros).
- errno values + names; `<ctype.h>` locale assumptions; math edge functions.
- (zlib specifically will want: correct `<unistd.h>`/`<fcntl.h>` for gzio file
  I/O, `off_t`/`lseek`, and whatever the gzgetc fast-path macro assumes.)

## How to work it
Bring up a real project → when it fails on a *library* symbol/assumption (not a
parser bug), add the concrete gap here with the project + call site, implement
the smallest crtl piece that satisfies it, land green (`make lib-test`), tick it
off. Keep gcc's libc as the oracle for behaviour.

## Gate
Per-item: the crtl addition compiles + the consuming project advances; `make
lib-test` stays green. Ongoing ticket — never "done", pruned as the corpus grows.

## Collected gap: `<inttypes.h>` (2026-07-20, Track B — CLOSED)

**Was:** 15 PRI macros and **zero SCN macros**, so any `scanf("%" SCNd64, &v)`
failed — and failed confusingly, because a missing PRI/SCN macro is not an error
at its definition, it is an undefined identifier inside string concatenation,
which surfaces as a syntax error some distance from the cause. Also declared
`strtoimax`/`strtoumax` with **no implementation anywhere in `lib/crtl/src`** —
exactly the "declared-but-unimplemented" category this ticket lists first.

**Now:** the full C99 set — PRI and SCN, for d/i/u/o/x/X, across
8/16/32/64/LEAST/FAST/PTR/MAX — plus `imaxdiv_t`, `imaxabs`, `imaxdiv`, and real
bodies for `strtoimax`/`strtoumax` in `lib/crtl/src/stdlib.c`.

**The part worth remembering:** the first draft was written from glibc's table
and was WRONG in two groups, because our `<stdint.h>` is not glibc's:

| type | glibc LP64 | ours | consequence |
| --- | --- | --- | --- |
| `intmax_t` | `long` | `long long` | MAX group is `"ll*"`, not `"l*"` |
| `int_fast16_t` / `int_fast32_t` | `long` | `long` | FAST16/32 are `"l*"`, not plain |
| `int64_t` | `long` | `long long` | 64-bit group is `"ll*"` |

None of these warn at the call site — they are varargs, so a wrong modifier
reads the wrong number of bytes off the stack and prints garbage. The header now
says this at the top so the next editor re-derives rather than assumes.

Gated by `test/crtl_inttypes.c` in `make lib-test` (exit 42 on success, like the
other `crtl_*.c` tests). It is deliberately **printf-free**: a wrong length
modifier IS a varargs bug, so a printf-based check would be testing the bug with
the bug — it compares the macro strings instead. Note gcc returns 1, not 42, on
this file and must not be "fixed" to agree: it asserts our ABI, and only the
8/16/32-bit and LEAST groups are common ground with glibc.

### Separate finding, NOT fixed here

Any crtl C program that calls `printf` dies at runtime under the current pin:

```
/tmp/p: symbol lookup error: /tmp/p: undefined symbol: __pxx_fegetround
```

Reproduces with a bare `printf("hi %d\n", 42)`, so it is nothing to do with
inttypes. `__pxx_fegetround` is registered by `compiler/cparser.inc` (~line 7148),
so this is pin lag — the pinned v222 predates it — not a live defect in HEAD.
Worth confirming after the next `make pin`; it is also why the existing
`crtl_*.c` tests are all exit-code based rather than printing anything.

## Declared-but-unimplemented sweep (2026-07-20, Track B)

Ran the ticket's own first category as an actual sweep rather than waiting for
the next project to trip over it: every `extern` function declared in
`lib/crtl/include/**` checked for a definition in `lib/crtl/src/**`, then each
survivor probed by taking its address, linking, and running.

**107 declared, 23 with no visible definition, exactly 1 real gap.** The other 22
resolve and were noise in the static check, worth recording so nobody re-chases
them:

- `__pxx_fegetround` / `__pxx_fesetround` / `__pxx_setjmp` / `__pxx_longjmp` —
  registered by the compiler (`cparser.inc`), not library symbols.
- `ceil floor fmod sqrt hypot log2 log10 cosh sinh tanh cos sin tan` — bind to
  Pascal RTL routines, or reach `__crtl_*` through the math.h macros.
- `ioctl mremap msync chmod umask` — all link and run.

**The one real gap: `exp2`.** Declared in `<math.h>`, defined nowhere. A C
program calling it compiled, linked, and then died at run time with
`undefined symbol: exp2` — the worst-behaved shape in this category, because
nothing catches it until the program is already running.

Implemented as `exp(x * ln2)` with ln2 carried as a double-double, so the
product keeps its low bits rather than losing them to a rounding before the
exponential (which is where a naive `exp(x * M_LN2)` drifts for large |x|).
Exact powers of two return `ldexp` directly — `2^k` must be *exact* for integral
k, and routing those through the series would round. Judged against 120-digit
references: 16 cases, all correctly rounded, 0 ulp. Gated as
`test/crtl_exp2.c` in `make lib-test`.

## Standing-collector note

This ticket is an **ongoing collector by design** — its own status line says so —
so it does not have a "done" state and should not sit in the ready queue as if it
did. The currently-collected batch (inttypes completeness + this sweep) is
closed. File the next batch against it when a project trips over something; the
sweep above is cheap to re-run and worth repeating after any header change.

