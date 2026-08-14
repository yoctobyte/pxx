---
track: C
prio: 55
type: bug
summary: "Under `--strict-uses`, the pxxcio heap-bridge functions (`__pxx_malloc`/`_free`/`_realloc`/`_atexit`) are emitted as UNDEFINED DYNAMIC IMPORTS instead of resolving to their Pascal bodies, so the binary compiles clean and dies at load with `undefined symbol: __pxx_malloc`. This is the second, distinct failure mode carved out of bug-a-threadsafe-segfaults-on-every-nilpy-program."
---

# `--strict-uses` turns the pxxcio C bridge into undefined dynamic imports

- **Type:** bug (compiles clean, fails at LOAD) — **Track C** (the C link model
  / crtl bridge; route to A if the decision turns out to live in the ELF
  writer's extern classification).
- **Split out of** [[bug-a-threadsafe-segfaults-on-every-nilpy-program]], which
  fixed the *other* failure mode on the same file and explicitly warned: "the
  two failure modes differ, which suggests the strict path and the plain path
  break at different points. Worth not assuming one fix covers both." It was
  right — they were unrelated.

## Reproduce

```
$ ./compiler/pascal26 --strict-uses --threadsafe test/test_nilpy_dotted_package_import.npy /tmp/d3
note: reportlab_lib_pagesizes -> mimic_reportlab_lib_pagesizes (shim, subset)
ok: /tmp/d3  [code=2758761B  data=73144B  bss=79340B  procs=2312]
$ /tmp/d3
/tmp/d3: symbol lookup error: /tmp/d3: undefined symbol: __pxx_malloc
```

## What is actually different

`objdump -T` on the two builds (**not** `readelf`, which is blind on pxx
binaries) is the whole diagnosis:

| build | `__pxx_*` dynamic symbols |
|---|---|
| `--threadsafe` | **none** — resolved internally, runs correctly |
| `--strict-uses --threadsafe` | `__pxx_malloc`, `__pxx_free`, `__pxx_realloc`, `__pxx_atexit`, `__pxx_atexit_run` all `DF *UND*` |

So under strict the C side's `extern void *__pxx_malloc(long)` stops resolving
to the Pascal body in `lib/rtl/pxxcio.pas` and is classified as an ordinary
external — i.e. a libc import — which links clean and cannot possibly resolve,
because these are pxx-internal symbols that no libc has.

**The compiler already knows this is a hazard and says so elsewhere.** The
`--strict-uses` diagnostic on the same file for a different symbol spells out
exactly this failure mode:

```
error: __pxx_pipe2 needs the thread-safe runtime: rebuild with --threadsafe
  (<pthread.h> lowers onto the pxx thread PAL, which that flag selects; without
   it this would import a pxx-internal symbol from libc and fail at load)
```

That is the guard working for `__pxx_pipe2` and **not** working for the pxxcio
heap bridge. The interesting question is why one is caught and the other is not
— the answer probably generalises to a rule rather than a fifth special case.

## Not a missing `uses`

The obvious hypothesis is wrong and was checked: both `lib/pcl` units that pull
a `.c` file (`mimic_reportlab_pdfbase`, `mimic_reportlab_pdfgen`) already carry
`uses pxxcio` **explicitly**, with a comment saying why:

```pascal
{ pxxcio supplies the heap bridge the C backend allocates through —
  without it the link leaves __pxx_malloc unresolved. }
uses pxxcio, pylib, '../vendor/pdfgen/pdfgen.c';
```

`grep` confirms no `lib/pcl` unit pulls a `.c` without also using `pxxcio`. So
the reference and its provider are both present in source; something in the
strict path stops the *definition* reaching the C translation unit's view.

Note also that the strict build is **larger** than the non-strict one
(2758761 vs 2755587 bytes of code), which is the opposite of what "fewer
transitive units" predicts and is worth explaining rather than dismissing.

## Why it matters beyond this one file

This is the **last blocker** on the `--strict-uses` corpus sweep: that sweep
produced exactly one finding in 1660 sources, and it is this file. With the
`--threadsafe` hang now fixed, the table stands at:

| flags | result |
|---|---|
| (baseline) | compiles, runs, correct |
| `--strict-uses` | compile error: add `--threadsafe` |
| `--threadsafe` | **now correct** (was SIGSEGV/hang) |
| `--strict-uses --threadsafe` | compiles, then `undefined symbol: __pxx_malloc` |

So [[bug-pascal-uses-is-transitive]] and the default-flip decision behind
[[project_strict_uses_is_the_honest_instrument]] are one mechanism away from
clear.

## Suspected direction (unverified — measure, do not reason)

A pxx-internal `__pxx_*` symbol should never be emitted as a dynamic import.
That looks like an invariant the ELF writer or the C extern classifier could
assert outright — the same shape as the `IREmitCodeCall(0)` guard added in the
parent ticket, where one check at the choke point covered ~50 call sites. If
that holds, the fix is a refusal plus whatever makes the definition visible,
not a per-symbol allowlist.

## Gate

`--strict-uses --threadsafe test/test_nilpy_dotted_package_import.npy` compiles
**and runs**; `objdump -T` shows no `__pxx_*` undefined dynamic symbols in any
build configuration; the `--strict-uses` corpus sweep comes back clean.
