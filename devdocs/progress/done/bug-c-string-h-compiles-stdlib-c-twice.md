---
summary: "#include <string.h>, with nothing used, compiles lib/crtl/src/stdlib.c TWICE — 51 functions get two bodies each. #include <stdlib.h> alone does not"
type: bug
track: C
prio: 60
---

# `#include <string.h>` compiles `stdlib.c` twice

- **Type:** bug — Track C (C frontend, crtl module auto-pull)
- **Status:** done
- **Opened:** 2026-08-05
- **Found by:** the duplicate-definition warning added for
  [[bug-a-duplicate-definition-silently-accepted]]. The warning is correct; this
  is what it found, and it is why the C half of that warning is not enabled yet.

## Repro

```c
#include <string.h>
int main(void) { return 0; }     /* nothing used at all */
```

With the duplicate-definition check compiled into the C frontend, this emits
**51 warnings** — every function in `lib/crtl/src/stdlib.c` gets a second body:
`malloc`, `free`, `calloc`, `realloc`, `qsort`, `bsearch`, `atoi`, `atof`,
`strtod`'s helpers, the `__pxx_builtin_*` bit intrinsics, `pxx_env_*`, and so on.

```c
#include <stdlib.h>
int main(void) { void *p = malloc(4); free(p); return 0; }   /* 0 warnings */
```

So it is specific to reaching `stdlib.c` **through** `<string.h>`, not to
`stdlib.c` itself.

## Why it is not just noise

Two full copies of a module are compiled and emitted. Beyond the size, it is the
positional-binding hazard from the parent ticket in production form: calls
resolved between the two copies bind to the first body, calls after bind to the
second. They are identical today, so nothing misbehaves — but nothing *checks*
that they stay identical either, and the second silently wins.

## An include guard does NOT fix it — measured, not assumed

The obvious answer is "protect the header", and it does not work. Two reasons,
in order:

1. **`stdlib.h` already has a guard** (`PXX_CRTL_STDLIB_H`), like every crtl
   header. The header is not the thing being pulled twice — the **source** is.
2. **Guarding the source does not help either.** Wrapping
   `lib/crtl/src/stdlib.c` in `#ifndef PXX_CRTL_STDLIB_C` and rebuilding leaves
   the count at **51 warnings and a byte-identical code size** (159754B before
   and after). The second copy never passes through that `#ifndef` at all.

### Why: the preprocessor is per-invocation, as Pascal's defines are per-unit

**User, 2026-08-05: "in pascal, defines are local to the unit."** That is
exactly it, and the code says so plainly. `CPreprocess`
(`compiler/cpreproc.inc:2605`) begins by clearing everything:

```pascal
CPMCount := 0;
for i := 0 to CPREP_MACRO_HASH_SIZE - 1 do CPMHashHead[i] := -1;
...
CPAddLiteral('__linux__', '01');   { predefines re-seeded }
```

so the macro table is scoped to one *invocation*. That is right for Pascal,
where `{$DEFINE}` is unit-local — and wrong for C, where `#define` is
translation-unit-global and an include guard has to survive every nested include
in that TU. `cparser.inc:8134` calls `CPreprocess` a **second** time for the
synthetic pull, and that call starts from a clean table, so no guard written
anywhere can be visible to it.

### And the dedup marker that should have caught it anyway

`CPullCrtlForPrototypes` synthesises `#include <stdlib.h>` lines and runs
`CPreprocess` over them. If macro state carried across, that synthetic include
would hit `PXX_CRTL_STDLIB_H` and expand to nothing — the module would never be
pulled a second time, and the bug would not exist. **It pulls, so the guard
macros from the earlier pass are not visible there.** Every include guard,
header or source, is bypassed on that path by construction.

So this cannot be fixed in crtl. It is compiler-side bookkeeping: either the
late pull consults `CPMarkCrtlSrcPulled` (compiler state, immune to the macro
table being reset), or the macro table is carried into the synthetic
preprocess so ordinary guards do their job.

The second option is the more principled one — it would make guards work
everywhere on that path rather than special-casing the crtl sibling pull — but
it is also the one more likely to change behaviour elsewhere, so measure the
pulled-region pass counts before choosing.

## Lead

`lib/crtl/src/string.c` includes only `<stddef.h>` and `<string.h>` — it does
**not** include `<stdlib.h>`, so the first pull is not a plain nested include.
`cparser.inc` has a second mechanism, described in its own comment:

> *After pass 1: any proc still marked external (= prototype with no definition
> anywhere in the TU) whose name is a known crtl libc function pulls its crtl
> module, exactly as if the program had included the header.*

`CrtlSrcPulled[]` / `CrtlSrcPulledCount` (`defs.inc:2060`) are plain globals,
**never reset** — not by `CPreprocess`, not anywhere — and *both* pull sites do
consult them (`cpreproc.inc:2125` for the header-driven pull, `:2326` for an
explicit `#include "...c"`). So the dedup is present and survives the second
invocation, and it still fails.

That leaves the comparison itself:

```pascal
for i := 0 to CrtlSrcPulledCount - 1 do
  if CrtlSrcPulled[i] = src then begin Result := True; Exit; end;
```

an **exact string match on the path**. The two pulls construct that path by
different routes — the header-driven one derives it from the already-resolved
header path (`CPCrtlSrcOf`: prefix up to `crtl/include/`, swapped for
`crtl/src/`), while the late pull re-resolves a synthetic `#include <stdlib.h>`
against the include search path. Two spellings of the same file (relative vs
absolute, or a differing prefix) miss each other and the module is pulled again.
That is the thing to confirm first: print both strings at the two call sites.

**Also worth fixing while there:** the marker array is bounded by
`MAX_C_INCLUDE_DIRS` (= 64, *"user `-I` C include search roots"*) — the wrong
constant for a list of pulled sources. crtl has far fewer than 64 `.c` files so
it is not reachable today, but past the cap `CPMarkCrtlSrcPulled` silently stops
recording and every later module loses its dedup.

## The check that found it

Ready to enable in `cparser.inc` at the `{ Otherwise, it has a body! }` site,
once this is fixed — it is the same three-term condition as the Pascal side:

```pascal
if (Procs[procIdx].BodyAddr >= 0) and CProcHasLocalDef[procIdx]
   and (ProcUnitIdx[procIdx] = CurrentUnitIdx) then
  Warn('duplicate definition of ''' + Procs[procIdx].Name + ''' ...');
```

`CProcHasLocalDef` is what keeps it quiet for crtl's **deliberate** overrides of
Pascal builtins (`malloc`, `memcpy`, `strtod` and dozens more are defined in
`compiler/builtin/*.pas` and again in `lib/crtl/src/*.c`) — without that term it
fired 88 times per C program. Verified correct on: two C bodies (warns),
prototype + definition (silent), `static` duplicate (warns), differing return
type (warns), and an ordinary crtl-using program (silent).

## Gate

`#include <string.h>` with nothing used compiles each crtl function once. Then
enable the C-side check above and confirm the whole `test/c*.c` set is silent.

---

## RESOLVED 2026-08-05 — it was not the preprocessor, and not the dedup marker

Both leads above were wrong, and the trace says so plainly. `--debug` shows
`stdlib.c` auto-pulled **exactly once**:

```
C preprocessor: auto-pull crtl impl .../lib/crtl/src/stdlib.c     <- one line, one time
```

`CrtlSrcPulled[]`'s exact-string comparison is fine; the two spellings never
differed. The macro-table reset is real (and does cause a *separate*, smaller
bug — see below) but it is not what compiled `stdlib.c` twice.

### The actual cause: pass 2 runs over the pulled region twice

`CLexAppend` **strips the user's EOF token** and merges the pulled tokens into
the same stream — deliberately, and `ParseCProgram`'s own comment says so
("pass 1/2 walk straight into them"). But `ParseCProgram` then runs:

1. `pass 2` from `firstIdx` to `tkEOF` — with the user EOF gone, this walks off
   the end of the user program and straight into the appended crtl region,
   compiling every pulled body. *(First copy.)*
2. `pass 2 over the pulled crtl region` from `crtlStart` — the dedicated block,
   which compiles them all again. *(Second copy.)*

`string.c` escaped only because it is pulled *inline* during the main
preprocess, so it sits in the user region and is compiled once.

**Fix** (`cparser.inc`): bound the main pass-2 loop by `crtlStart`.

```pascal
while (CurTok.Kind <> tkEOF) and ((crtlStart < 0) or (TokPos - 1 < crtlStart)) do
```

Anything appended *before* the crtl pull (pxxcio) still falls inside the loop,
exactly as it did.

**Measured**, `#include <string.h>` + empty `main`:

| | code | procs | dup warnings |
| --- | --- | --- | --- |
| before | 159754 B | 492 | 51 |
| after | 132374 B | 487 | 0 |

### The warning is now enabled

The C-side duplicate-definition check landed at the `{ Otherwise, it has a
body! }` site, as written above. `test/*.c` (373 files) and the 220-test
c-testsuite conformance battery are silent apart from one ticketed file.

### What it found on the way in — three real crtl duplicates, all fixed

1. **`time` / `__crtl_time`** — `stdlib.c` carried a seed-only stub
   `time(t) { if (t) *t = 0; return 0; }`. `time.h` does
   `#define time(t) __crtl_time(t)`, so in any TU that saw `<time.h>` first the
   stub *expanded to a second body for `__crtl_time`* — one that always returns
   0 — competing with the real PAL clock in `time.c`. Removed; `time.c` owns it.
2. **`gettimeofday`** — defined in both `sys/time.c` (microseconds, via
   `__pxx_realtime`) and `time.c` (seconds only, `tv_usec` always 0), and
   `time.c` includes `<sys/time.h>` so both landed in one TU. Whichever was
   pulled last decided the precision. `time.c`'s removed.
3. **`close`** — `netinet/in.c` defined a second `close` routing through
   `__pxx_socket_close`, so in any program doing sockets *and* file I/O every
   close went wherever pull order pointed. Removed; `unistd.c` owns it. Identical
   on POSIX (same syscall); the ESP-IDF half is
   [[bug-b-crtl-esp-close-cannot-dispatch-socket-vs-file]].

### What it found that is NOT fixed

`stdarg.h`'s six `static __pxx_va_*` helper **bodies** still compile twice when
a late pull re-includes the header past the macro-table reset — the reset lead
above was right about *this*, just not about `stdlib.c`. Root-caused (there is a
*third* `CPreprocess` invocation in between that clears the table) and filed as
[[bug-c-header-with-a-body-compiles-twice-across-the-macro-reset]]. One file of
373 warns.

**Not done, still worth doing:** `CrtlSrcPulled[]` is still bounded by
`MAX_C_INCLUDE_DIRS` (64, the wrong constant) — unreachable today, silent when
reached. Left as noted above.

Gate run: `gate.sh quick` GREEN, `gate.sh lib` GREEN, c-testsuite 219 pass /
0 fail / 1 skip native and i386, self-host fixedpoint converges.

## Log
- 2026-08-05 — resolved, commit 28a217c49.
