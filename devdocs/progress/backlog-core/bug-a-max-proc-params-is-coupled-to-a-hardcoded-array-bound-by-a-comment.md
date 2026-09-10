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
blocked-by:
  - bug-a-fourteen-compiler-internal-record-names-shadow-any-user-type
summary: "CORRECTED 2026-09-10, and the correction is the finding: there is no const-expr gap, and there is also no coupling to fix. TProc.Params keeps 32 slots whatever its bound says -- `array[0..31]`, `array[0..255]` and `array[0..MAX_PROC_PARAMS-1]` all emit the same code/data/bss/procs with SizeOf(TProc)=1344 -- so writing the constant there only makes the two LOOK coupled. The real blocker is bug-a-fourteen-compiler-internal-record-names-shadow-any-user-type: IsRecordType maps the NAME TProc to a builtin rec id before consulting any declaration, so defs.inc's TProc declaration is documentation and the bound never reaches the field offsets. What landed and stands: the thirteen cparser.inc staging locals and argUndecl now derive (locals DO fold), pptrdims had a genuine 6-element overflow, and the overflow diagnostic no longer says 16 when the limit is 32. MAX_PROC_PARAMS stays 32; raising it is a SIGSEGV at exactly 33 until the layout bug is fixed."
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

# CORRECTION (2026-09-10, same day): the comment was right and I was wrong

I filed this saying record-field bounds cannot fold the constant, then
"disproved" that with a two-line probe and landed `e9599a1b0` writing
`array[0..MAX_PROC_PARAMS-1]` into the field. **The probe was drawn from the
wrong population** -- a nine-line program with the constant declared eight
lines above -- and it folds there. In `defs.inc` the field keeps **32 slots
whatever the bound says**, a bare `array[0..255]` included, so my change was a
no-op that deleted a correct warning and left source that reads as coupled.
Reverted to the literal with the measurements written beside it; the layout
defect is now `bug-a-fourteen-compiler-internal-record-names-shadow-any-user-type` —
and it is a NAME-SHADOWING bug, not an array-bound one: fourteen internal record
names shadow any user type of the same name, so `type TProc = record ... end` in
an ordinary program silently gets the compiler's layout.

The original author's comment was accurate about the SYMPTOM and wrong only
about the mechanism (they said const-expr; it ignores a literal too). That is
CLAUDE.md's "comment vs code" rule going the other way: I decided the comment
was wrong, and the deciding evidence was a control that could not fail.

# The old section, kept because its premise is what broke

```pascal
Params : array[0..31] of TParam;   { literal 31: record-field bounds cannot
                                     use MAX_PROC_PARAMS-1 (const-expr gap) }
```

There is no const-expr gap. Measured 2026-09-10 with a two-line probe against
**both** the live compiler and `stable_linux_amd64/default/pinned`: a record
field declared `array[0..MAXP-1] of TP` compiles and reports 32 elements on
each. `defs.inc:4617-4625` — `CTypeFnRetPTypes` and eight siblings — have been
written `array[0..MAX_PROC_PARAMS-1]` all along, a few thousand lines below the
comment saying it cannot be done.

**Both halves of that paragraph are true and the conclusion drawn from them was
wrong.** Vars and locals do fold the constant; this record field does not size
itself from its bound at all, expression or literal. The siblings were a real
observation about a different construct.

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

# What is still broken

The original body blamed the segfault on the field holding 32 slots. **That was
right.** What was wrong was my belief that writing the constant into the bound
would widen it. With every *staging* array derived and `MAX_PROC_PARAMS = 64`:

| params | result |
| --- | --- |
| 32 | compiles and runs |
| 33 | **SIGSEGV (rc=139)** |
| 40, 64, 65 | SIGSEGV |

Measured on two independently built compilers — one seeded from `pinned`, one
from `compiler/pascal26` — so it is a source-level defect, not a miscompile.
`bss` grows by only **2848 bytes** at 64, which is the `abi.inc`/codegen local
vectors and nothing else: a widened `TProc.Params` would have added
`16384 * 32 * 40` = **21MB**. That delta is the clearest single sign the field
did NOT widen, and I read it as confirmation that it had — the number was in
front of me from the first build.

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
