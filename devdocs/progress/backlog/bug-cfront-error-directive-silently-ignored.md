---
track: C
prio: 75
type: bug
summary: "`#error` in a LIVE branch is silently ignored — the program compiles and runs. Any C source whose configuration guard says \"this build is unsupported\" is built anyway, usually with most of the file #if'd away. Found while scoping cpyext M5: it made a Cython module look like it compiled clean when 5000 of its 8000 lines had been discarded."
---

# `#error` compiles clean

- **Type:** bug (C preprocessor — SILENT, produces a truncated program) — **Track C**
- **Found:** 2026-08-02 while scoping cpyext M5
  ([[feature-nilpy-cpyext-c-api-from-source]]).

## Measured

```c
#include <stdio.h>
#if 1
#error this must stop the compile
#endif
int main(void){ printf("should never run\n"); return 0; }
```

```
$ ./compiler/pascal26 -Ilib/crtl/include -Ilib/crtl/src errdir.c /tmp/errdir
ok: /tmp/errdir  [code=182963B ...]
$ /tmp/errdir
should never run

$ gcc -o /dev/null errdir.c
errdir.c:3:2: error: #error this must stop the compile
```

`#warning` is likewise dropped (correct to not fail on, but it should be
reported).

## Cause

`CPHandleDirective` (`compiler/cpreproc.inc:~2300`) dispatches `if / ifdef /
ifndef / elif / else / endif / define / undef / include / pragma`. There is no
`error` or `warning` arm, and the chain ends without a fallback — an unknown
directive is silently discarded. So `#error` is not "ignored on purpose", it is
simply not a directive the preprocessor knows about.

## Why this matters more than it looks

`#error` is how real C libraries state a precondition. When it is a no-op, the
guard does not fail the build — it just leaves everything *behind* the guard
unreachable, because the same `#if` that reached the `#error` also excludes the
`#else` half holding the code. The result is a program that links, runs, and is
missing whatever the excluded region defined.

The worked example, and how this was found: **Cython's generated C** opens with

```c
#include "Python.h"
#ifndef Py_PYTHON_H
    #error Python headers needed to compile C extensions...
#elif PY_VERSION_HEX < 0x03080000
    #error Cython requires Python 3.8+.
#else
    ...8000 lines: the entire module...
#endif
```

pxx's `lib/cpyext/include/Python.h` defines no `PY_VERSION_HEX`, so the `#elif`
is true, both `#error`s were dropped, and **the whole module body was excluded**.
The file compiled "successfully"; the only symptom was `PyInit_cyadd` being
undeclared 3000 lines later. Five minutes were spent reading the wrong thing.
With gcc's behaviour it would have been one line of output.

## Fix

Two arms in `CPHandleDirective`:

- `#error <text>` when `CPActive` → `Error('#error: ' + <text>)`, using the
  same message path every other C diagnostic uses.
- `#warning <text>` when `CPActive` → emit to stderr and continue.

Both must respect `CPActive` — an `#error` inside a NOT-taken branch is
ordinary, extremely common, and must stay silent (`#if 0 / #error / #endif`).
That is the whole subtlety and it is already available.

Worth considering with it: a diagnostic for an unrecognised directive in a live
branch, so the next missing one is loud rather than silent. `#line` and the
`#ident`/`#sccs` GNU extensions are the realistic candidates; check the corpora
before making an unknown directive fatal.

## Gate

The repro above fails to compile with a message naming the text; `#if 0` around
an `#error` still compiles clean; `#warning` reports and continues; the C
corpora (zlib, sqlite, tcc, lua, quickjs) still build — several of them contain
`#error` inside guards that must remain not-taken, which is the real regression
risk and the reason the `CPActive` check is not optional.
