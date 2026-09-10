---
slug: bug-n-a-sys-stream-in-a-variable-has-no-methods-and-fails-at-run-time
track: N
type: bug
prio: 60
status: backlog
owner: ""
created: 2026-09-10
found-by: frankB
tags: [nilpy, sys, streams, silent, lekkerzeilen]
blocked-by: []
summary: "`h = sys.stdout` then `h.write(x)` COMPILES and dies at run time with `TypeError: object is not callable`, having written nothing. `sys.stdout`/`sys.stderr` are modelled as a bare fd INTEGER (AN_INT_LIT, 1 and 2) and an Integer has no methods. The dotted spelling `sys.stdout.write(x)` was fixed 2026-09-10 by wiring the three-segment table entries sys.stdin already had; this is the spelling the table cannot reach. The fix is to make a stream an OBJECT — pylib's TPyFile already is one — and it cannot land alone: PyParsePrintFile asserts `ASTKind = AN_INT_LIT` and value 1 or 2, so print's file= handling must move in the same change or every `print(..., file=sys.stderr)` goes red."
---

# Measured 2026-09-10, compiler `4d3d006cf973`

```python
import sys
h = sys.stderr
h.write("TO-STDERR\n")
```

```
compiles clean -> rc=217
Unhandled exception: TypeError: object is not callable
nothing on stdout, nothing on stderr
```

# Why this is worse than the sibling that was fixed

The dotted spelling failed at COMPILE time with `expected ':' before '.'` — loud,
located, cannot ship. This one is past every gate a compile can be. **A probe
that only asks "does it compile" reports the silent shape as the working one and
the loud shape as the broken one, which reverses the severity ordering**, and
that is how it was reported to a peer for an hour on 2026-09-10 before being
re-measured.

# The boundary

| shape | today |
| --- | --- |
| `print(..., file=sys.stderr)` | **works**, byte-identical to CPython, both streams |
| `sys.stdout.write(x)` / `.flush()` / `.isatty()` | **works** since 2026-09-10 |
| `sys.stdin.read()` / `.readline()` / `.isatty()` | works, and always did |
| `h = sys.stdout; h.write(x)` | **compiles, dies at run time** |
| `f = sys.stdout if c else sys.stderr` then `f.write(x)` | same |

Every working row goes through a name the dotted-call table can see. Nothing
reaches a stream through a VARIABLE, and real code does that constantly — a
routine taking a `stream` parameter is the ordinary way to write this.

# The fix, and why it is one change and not two

pylib's `TPyFile` (FFd, `write(AnsiString)`, `write(TPyBytes)`, `readline`) is
already the object a stream should be — `open()` returns one. Making
`sys.stdout` a `TPyFile` on fd 1 fixes BOTH spellings at once and deletes the
special case rather than growing a second path.

**But `PyParsePrintFile` reads the fd back out of the AST**:

```pascal
  if (CurASTNode < 0) or (ASTKind[CurASTNode] <> AN_INT_LIT) or
     ((ASTIVal[CurASTNode] <> 1) and (ASTIVal[CurASTNode] <> 2)) then
    Error('Nil Python: print file= expects sys.stdout or sys.stderr');
```

so the moment `sys.stderr` stops being an integer literal, the five working
`print(..., file=sys.stderr)` sites in lekkerzeilen/__main__.py go red. The two
have to move together, which is why this was NOT smuggled into the table patch
that fixed the dotted spelling.

# Positive control for whoever takes it

The three-line program above must exit 0 and put `TO-STDERR` on fd 2. And
`print(..., file=sys.stderr)` must still work — assert both, because a fix that
only satisfies the first is the regression this ticket exists to prevent.
