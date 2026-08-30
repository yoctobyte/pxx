---
prio: 50
track: A
type: bug
blocked-by: []
summary: "CModuleOfTok is STICKY: CMarkTokModule is only called for a path ending in `.c`, so returning from a crtl `.c` pull back into the enclosing `.h` never resets the attribution and every following token still reports that `.c` as its module. Blocks the remaining half of bug-c-a-header-reached-by-uses-discards-function-bodies-and-imports-them-instead: a bodied static after `#include <stdio.h>` cannot be told apart from one inside crtl's stdio.c. Filed by Track C -- the table lives in dbg_filetable.inc, which is Track A."
status: done
owner: frankA
---

# `CModuleOfTok` never resets when an include returns to its parent

## What it does today

`compiler/clexer.inc`, in the `# <line> "<path>"` marker handler:

```pascal
if CPathIsCModule(path) then CMarkTokModule(TokCount, path);
```

Only a path ending in `.c` starts a new module range. A `.h` deliberately
leaves the attribution alone, so that a file-scope `static` defined in a header
is attributed to the module that included it — which is right, and is what
`bug-c-static-functions-in-different-crtl-modules-collide` fixed.

The gap is the **return** edge. When crtl's `stdio.c` finishes and the
preprocessor resumes the header that pulled it, the marker naming that header
is a `.h`, so nothing is marked — and `CModuleOfTok`, which answers with *the
last range starting at or before the token*, keeps answering `stdio.c` for the
rest of the translation unit. The attribution is not "the module that included
this token", it is "the last `.c` we happened to enter", which is the same
thing only until the first return.

## Measured, at `450f36ae3ec4`

A `uses`d header with a bodied `static`, varying only what the header includes
above it:

| the header includes | attribution at the static | outcome |
| --- | --- | --- |
| nothing | none (-1) | correct |
| `"user.h"` (no crtl impl) | none (-1) | correct |
| `<stddef.h>`, `<stdint.h>`, `<stdbool.h>`, `<limits.h>`, `<errno.h>` | none (-1) | correct |
| **`<stdio.h>`, `<string.h>`** — headers with a crtl `src/*.c` sibling | **that `.c`** | **wrong** |
| `<stdio.h>` *below* the static | none (-1) at the static | correct |

The middle rows are the tell: `stddef.h` and `stdio.h` differ only in whether
crtl has an impl to auto-pull, and nothing about the static changes.

## Why Track C cannot fix it

`CMarkTokModule` / `CModuleOfTok` and the `CModRange*` arrays are in
`compiler/dbg_filetable.inc` and `compiler/defs.inc`, both **Track A**. Every
shape of the fix needs storage or an accessor there, so this is filed rather
than done, per the shared-internals rule.

## What it blocks

`bug-c-a-header-reached-by-uses-discards-function-bodies-and-imports-them-instead`.
That ticket's fix has to compile the body of a `static` from *the header the
user named* while leaving crtl's own modules on the path that already works —
i.e. it needs exactly the question `CModuleOfTok` looks like it answers. With
the stickiness it covers only the rows above the bold one; the common shape
(`#include <stdio.h>` at the top of a header, a `static inline` below it) stays
broken.

## The shape I would build, and why this spelling

**Mark on the return edge with the innermost enclosing `.c`, or a sentinel when
there is none.** Concretely, when the marker handler sees a non-`.c` path, mark
with the `.c` the include stack is *currently* inside — which the preprocessor
knows and the lexer does not, so the preprocessor has to say it. It already
emits the marker; one additional field or directive carries the answer.

This is a strict improvement to the existing consumer, not a trade against it.
The duplicate-definition check wants "the module that included this header",
and this gives it exactly that: `stdarg.h` pulled from `fcntl.c` attributes to
`fcntl.c`, pulled from `unistd.c` attributes to `unistd.c` — still two modules,
still no false duplicate warning. Today it gets the right answer for the same
reason a stopped clock does, and only until the first return edge.

A sentinel for "no enclosing `.c`" is needed because `CMarkTokModule` interns a
path and every interned path is a valid id; there is no way to mark *absence*.
Either `CModuleOfTok` gains a reserved id, or the range table gains an explicit
"none" marker.

## What a fix must assert

- The table above: all six rows attribute correctly, `<stdio.h>` included.
- `bug-c-static-functions-in-different-crtl-modules-collide` stays fixed —
  `sysret` in `fcntl.c` and `unistd.c` still do not warn, and two same-named
  statics in ONE real `.c` still do.
- Self-host fixedpoint, and the gtk set (Pascal programs binding C headers,
  which is the population that reaches this code hardest).

## Log
- 2026-08-30 — filed by frankC while fixing the header-static bug. The partial
  fix that landed uses `CModuleOfTok(TokPos - 1) < 0` as its scope term and is
  correct exactly where the attribution is; this ticket is the rest of it.

## RESOLVED

Baseline `d7d17e1bd553` reproduces the table exactly; `8035e124b67d` (the same
tree plus the fix) gets all five rows right.

| the header includes | before | after |
| --- | --- | --- |
| nothing | none | none |
| `"user.h"` | none | none |
| `<stddef.h>` `<stdint.h>` `<limits.h>` `<errno.h>` | none | none |
| **`<stdio.h>`, `<string.h>`** | **`crtl/src/stdio.c`** | **none** |
| `<stdio.h>` below the static | none | none |

### The lexer cannot do this alone — measured, not assumed

The tempting fix is to reconstruct the include stack in the lexer from the
marker paths, which needs no preprocessor change. **It does not work, and a
probe on the marker handler says why**: the path sequence is not a well-formed
stack trace. An include-guarded header that was already pulled emits an enter
marker with no matching return, so a real run produces

```
src/stdio.c -> stdarg.h -> stddef.h -> errno.h
```

with no returns between them, and

```
tok=44436 stdarg.h
tok=44436 src/stdarg.c      <- enter
tok=44436 stdarg.h          <- return
tok=44436 src/stdarg.c      <- enter again, same token
```

Only the preprocessor knows the real stack, which is what the filed shape said.

### The fix

- `cpreproc.inc`: `CPEnclosingCModule` scans `CPPathAtDepth[CPCurDepth..0]` for
  the innermost `.c`; `CPSyncLine` emits it as an optional **second** quoted
  field, `# <line> "<path>" "<enclosing.c>"`, omitted when there is none or when
  it is the primary path. (`CPPathAtDepth` is one spelled bound as of frankS's
  `85114f34f`, so this is a three-line loop against one constant.)
- `clexer.inc`: parse the optional second field; mark with `path` if it is a
  `.c`, else with the enclosing module, else **mark none**.
- `dbg_filetable.inc`: `CMarkTokNoModule`, on a shared `CMarkTokModuleId`. The
  sentinel is `-1` — no new value needed, because `CModuleOfTok` already returns
  `-1` for "no range covers this token" and every consumer already reads that as
  "the main source, not a C module". What was missing was the ability to *mark*
  absence rather than only to never mark.

### The regression properties the ticket asked for

- `sysret` attributes to **`fcntl.c`** and **`unistd.c`** — two distinct modules,
  measured with a probe on `ProcCModule`, so
  `bug-c-static-functions-in-different-crtl-modules-collide` still holds. Two
  same-named statics in one real `.c` still warn (checked: it fires).
- The six `__pxx_va_*` statics still attribute to `stdarg.c`.
- Self-host fixedpoint, 1 round; `gate.sh quick` GREEN.
- **gtk set**: all five compile in both invocations (bare, and with `GTK3_INC`),
  identically to the pinned binary, and run under `xvfb` with byte-identical
  output apart from pids and timestamps. `test_c_gtk_types`' two
  `GLib-GObject-CRITICAL` lines are **pre-existing** — the pinned binary emits
  them too.

### One consequence worth stating: gtk binaries grow ~16 KB

`test_c_gtk_window` goes 143016 → 155304 bytes of code with **`procs=14066` on
both**. Same procs, more of them with bodies: a header `static` whose
attribution used to read as "inside a crtl `.c`" was imported instead of
compiled, and now compiles. That is the correct direction and is the half of
[[bug-c-a-header-reached-by-uses-discards-function-bodies-and-imports-them-instead]]
this ticket exists to unblock, arriving as a side effect rather than as that
ticket's own change. It is deliberate, it is measured, and the gtk set — the
population that reaches this hardest, and the one whose five tests broke the
last time this area moved — is unchanged in behaviour.
- 2026-08-30 — resolved, commit PENDING-COMMIT.
