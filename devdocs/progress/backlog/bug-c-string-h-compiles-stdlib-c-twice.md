---
summary: "#include <string.h>, with nothing used, compiles lib/crtl/src/stdlib.c TWICE — 51 functions get two bodies each. #include <stdlib.h> alone does not"
type: bug
track: C
prio: 60
---

# `#include <string.h>` compiles `stdlib.c` twice

- **Type:** bug — Track C (C frontend, crtl module auto-pull)
- **Status:** backlog
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

## Lead

`lib/crtl/src/string.c` includes only `<stddef.h>` and `<string.h>` — it does
**not** include `<stdlib.h>`, so the first pull is not a plain nested include.
`cparser.inc` has a second mechanism, described in its own comment:

> *After pass 1: any proc still marked external (= prototype with no definition
> anywhere in the TU) whose name is a known crtl libc function pulls its crtl
> module, exactly as if the program had included the header.*

`CPMarkCrtlSrcPulled` guards the include-driven pull. The suspicion is that the
late external-resolution pull does not consult the same marker, or marks under a
different path spelling, so a module already pulled once is appended again.

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
