---
prio: 50
track: A
type: bug
blocked-by: []
summary: "CModuleOfTok is STICKY: CMarkTokModule is only called for a path ending in `.c`, so returning from a crtl `.c` pull back into the enclosing `.h` never resets the attribution and every following token still reports that `.c` as its module. Blocks the remaining half of bug-c-a-header-reached-by-uses-discards-function-bodies-and-imports-them-instead: a bodied static after `#include <stdio.h>` cannot be told apart from one inside crtl's stdio.c. Filed by Track C -- the table lives in dbg_filetable.inc, which is Track A."
status: new
owner: ""
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
