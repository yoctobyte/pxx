---
track: C
prio: 75
type: bug
summary: "`#error` in a LIVE branch is silently ignored — the program compiles and runs. Any C source whose configuration guard says \"this build is unsupported\" is built anyway, usually with most of the file #if'd away. Found while scoping cpyext M5: it made a Cython module look like it compiled clean when 5000 of its 8000 lines had been discarded."
status: done
owner: claude-AC@opus5
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

## Resolution 2026-08-03 (claude-AC@opus5)

Two arms in `CPDirective` (the ticket said `CPHandleDirective`; the procedure is
named `CPDirective`), both gated on `CPActive`:

- `#error <text>` -> `ErrorAt(CPCurLine, '#error in ' + CPCurPath + ': ' + text)`.
  `ErrorAt` rather than `Error` because the parser has not run yet — `Error`
  takes its line from `CurTok`, which during preprocessing still points at a
  token from a previous file.
- `#warning <text>` -> reported and compilation continues, following the
  existing `pascal26:<line>: warning: ...` idiom.

The message text is **not** macro-expanded, matching gcc: the point is to echo
what the source literally says.

The `CPActive` guard is the whole subtlety, as the ticket said, and the corpora
confirm the stakes: **1227** `#error` directives across `library_candidates/`,
`lib/crtl/` and `lib/cpyext/`, essentially all behind guards that must stay
not-taken.

### It immediately found three real preprocessor bugs

This is the part worth recording. Turning `#error` on dropped
`make test-c-conformance` from "219 pass" to **216 pass, 3 fail** — not a
regression, but three pre-existing defects that had been invisible *because*
`#error` was a no-op. The suite had been reporting green on tests whose only
assertions were `#error`s.

| test | defect |
| --- | --- |
| 00075, 00145 | `?:` had no precedence level in the `#if` evaluator at all — [[bug-cfront-if-ternary-unimplemented]] |
| 00152 | `#line` unimplemented, and `__LINE__` read as 0 inside `#if` — [[bug-cfront-line-directive-unimplemented]] |

Both were fixed in the same commit rather than skipped, so the suite is back to
**219 pass, 0 fail**, 1 known skip (VLA) — and now genuinely, since the `#error`
assertions actually fire.

That was the ticket's own argument, demonstrated: a no-op `#error` does not make
a build succeed, it makes the guard's failure land somewhere else and much later.

### Unknown-directive diagnostic — deliberately NOT added

The ticket floated failing on unrecognised directives. Not done: `#line` turned
out to be a real gap rather than a candidate for a fallback error, and with it
implemented the remaining unknowns are the `#ident` / `#sccs` GNU extensions,
which are legitimately ignorable. Making unknown directives fatal against 1227
`#error`s' worth of corpus guards is risk without a demonstrated defect behind
it. Reconsider if one shows up.

### Verified

| check | result |
| --- | --- |
| the ticket's repro | `pascal26:3: error: #error in e1.c: this must stop the compile`, exit 1 |
| `#if 0` / `#ifdef` undefined / not-taken `#elif` around an `#error` | compiles clean |
| `#warning` | reports and continues, exit 0 |
| `test/cerror_directive.c` | **new**, gated, exit 42 — pins the SILENT half (the regression risk) |
| `test/cerror_directive_fail.c` | **new**, gated must-fail — greps the diagnostic for the message text, so "it failed" is not enough |
| `test/cpreproc_cond_line.c` | **new**, gated, exit 42 under gcc and pxx |
| `make test-c-conformance` | 219 pass, 0 fail, 1 known skip |
| corpora: lua, cJSON, zlib, duktape, quickjs, sqlite parity | all PASS |
| `tools/gate.sh quick` | GREEN |

## Log
- 2026-08-03 — resolved; found and fixed three exposed preprocessor bugs with it.
- 2026-08-03 — resolved, commit 312778a4b.
