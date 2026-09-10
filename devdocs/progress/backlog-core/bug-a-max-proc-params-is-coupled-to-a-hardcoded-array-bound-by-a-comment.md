---
slug: bug-a-max-proc-params-is-coupled-to-a-hardcoded-array-bound-by-a-comment
track: A
prio: 45
type: bug
status: backlog
owner: ""
created: 2026-09-10
found-by: frankH
tags: [core, limits, cparser, sdl, lekkerzeilen]
blocked-by: []
summary: "The COUPLING is fixed: every parameter buffer now derives its bound from MAX_PROC_PARAMS (the `const-expr gap` the old comment blamed does not exist — both the live compiler and the pinned seed fold `MAX_PROC_PARAMS-1` in a record field bound, and nine sibling globals in defs.inc had named the constant all along). What remains is the part the coupling was hiding: with every literal widened and the constant at 64, a 33-parameter routine STILL segfaults the compiler — on a bare `external` DECLARATION, in the Pascal and C frontends alike, below RegisterProc. Cause not yet located. Until it is, MAX_PROC_PARAMS cannot be raised and `import SDL2/SDL.h` stays blocked at gcc's `_mm512_set_epi8` (64 params)."
---

# What was fixed

Every parameter-indexed buffer now says `MAX_PROC_PARAMS`:
`TProc.Params` (`defs.inc`), the thirteen `cparser.inc` locals, and the
`argUndecl` call-argument mirror with its two `<= 31` guard literals.

`pptrdims` was genuinely out of bounds and nobody had hit it: it is indexed
`nparams * MAX_ARR_DIMS + pmi` — up to `31*6+5 = 191` — and was declared
`array[0..31 * MAX_ARR_DIMS - 1]`, i.e. `0..185`. **Six elements short**, for a
pointer-to-multidimensional-array parameter in one of the last slots. Found by
widening, not by a test.

# The comment was the defect

```pascal
Params : array[0..31] of TParam;   { literal 31: record-field bounds cannot
                                     use MAX_PROC_PARAMS-1 (const-expr gap) }
```

There is no const-expr gap. Measured 2026-09-10 with a two-line probe against
**both** the live compiler and `stable_linux_amd64/default/pinned`: a record
field declared `array[0..MAXP-1] of TP` compiles and reports 32 elements on
each. `defs.inc:4617-4625` — `CTypeFnRetPTypes` and eight siblings — have been
written `array[0..MAX_PROC_PARAMS-1]` all along, a few thousand lines below the
comment saying it cannot be done. The gap was never real; the comment was, and
it is what kept the constant unraisable for as long as anyone believed it.

**This is CLAUDE.md's "comment vs code" rule with the comment winning for
months.** The way out was a probe, not a reading.

# `{$if}` over a Pascal const does not survive the pinned seed — do not guard this way

The first attempt at enforcing the coupling was
`{$if MAX_PROC_PARAMS <> 32} {$error ...} {$endif}` in `defs.inc`. It builds
locally: `make compiler/pascal26` converges, `--tier quick` is green, and its
positive control fires correctly when the constant is changed. **The pinned
compiler refuses it outright:**

```
pascal26:0: error: conditional directive: `MAX_PROC_PARAMS` has no integer
value here, so it cannot be compared (an undefined symbol, or one defined
without a value)
```

`{$if}` evaluates *preprocessor* symbols; the live compiler has grown the
ability to see a Pascal `const` there and the pin has not. So the only row that
caught it was `gate.sh quick`'s `self-host fixedpoint`, reporting
`round 1 — seed could not compile the compiler` and nothing else. Exactly the
defect class CLAUDE.md says that canary exists for. **A compile-time guard in
`compiler/**` must be expressed in something the PIN accepts.**

# What is still broken, and it is not what this ticket originally said

The old body blamed the segfault on the un-widened literal. That was a
hypothesis and it is **false**. With every literal derived and
`MAX_PROC_PARAMS = 64`:

| params | result |
| --- | --- |
| 32 | compiles and runs |
| 33 | **SIGSEGV (rc=139)** |
| 40, 64, 65 | SIGSEGV |

Measured on two independently built compilers — one seeded from `pinned`, one
from `compiler/pascal26` — so it is a source-level defect, not a miscompile.
`bss` grows by 2848 bytes at 64, confirming `TProc.Params` really did widen.

The crash needs **no body and no call site**. All three of these die:

```pascal
procedure wide(a0: Integer; ... a32: Integer); external;   { declaration alone }
procedure wide(...); begin WriteLn(a0); end;               { defined, never called }
wide(1, ..., 1);                                           { defined and called }
```

and the C frontend fails identically at the same boundary, so it is **below
both parsers** — the staging arrays in `pasparser_proc.inc` and `cparser.inc`
are all derived and all sized 64 here. `RegisterProc`'s own guard
(`nParams > MAX_PROC_PARAMS`) is correct and not reached.

**Next step for whoever takes this:** build with `-g -O2`, `source
tools/pxx-gdb.py`, and get a real frame. Every cheap narrowing above is spent;
the remaining question is one backtrace wide.

# What it blocks

`import "/usr/include/SDL2/SDL.h"` reaches gcc's `<immintrin.h>` via
`SDL_cpuinfo.h`/`HAVE_IMMINTRIN_H`. Current wall, measured today:

```
pascal26:3913: error: C function definition: more than 32 parameters not
supported (MAX_PROC_PARAMS)
  near: char __q01  char __q00  >>>  return
```

`_mm512_set_epi8` takes 64 — the structural maximum over gcc's x86 intrinsic
headers, since AVX-512 is 512 bits.

# The fork worth measuring before doing the work

Past the parameter list sits `__m512i`, a vector type pxx does not have, so
raising the limit may only move the wall a few tokens. The alternative is a
pxx-owned `immintrin.h` that declares nothing and fails by NAME — honest, since
pxx implements no AVX-512 intrinsics either way. **Measure which wall comes
next before choosing.** The 33-param crash above is worth fixing regardless: it
is a segfault on ordinary Pascal, independent of intrinsics.
