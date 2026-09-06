---
slug: bug-a-comp-renders-as-an-integer-because-it-aliases-int64
title: "`WriteLn(Co)` on a Comp prints `5`, fpc prints `5.000000000000000000E+0000` — Comp aliases Int64 and so loses its real-valued face"
track: A
prio: 20
type: bug
status: backlog
owner: ""
created: 2026-09-06
found-by: frankwasm
blocked-by: []
summary: "pxx maps `comp` to `tyInt64` (pasparser_lval.inc:8114), so a Comp variable renders through the INTEGER writer: `WriteLn(Co)` prints `5` where fpc 3.2.2 prints `5.000000000000000000E+0000`, because Comp is a real-valued type there (a 64-bit integer-encoded float). The VALUE is correct and now matches fpc on every row — that was bug-a-a-float-assigned-to-an-integer-lvalue-moves-the-bits-instead-of-converting, fixed in 3e2bca576. Only the rendering differs, and it differs on source someone meant to write. NOT settled which way this should go: see the fork below."
---

# Measured 2026-09-06, `3e2bca576`

```pascal
var Co: Comp; D: Double;
D := 4.7; Co := D; WriteLn(Co);
{ pxx  5                          }
{ fpc  5.000000000000000000E+0000 }
```

Same for every row: values agree (5 / 2 / 4 / -5 / -2 / 0 / 2), rendering does
not. `comp` is aliased at `pasparser_lval.inc:8114`:

```pascal
else if CaseEqual(nm, 'comp') then Result := tyInt64
```

so nothing downstream can tell a Comp from an Int64 — including `Write`.

# The fork, stated rather than decided

**It may be a bug.** A program's observable output differs, on source that
compiles under both and that the author meant to write. That is the ordinary
definition of a compat defect, and `Str`/`Write`/`WriteLn` are exactly where a
type's identity is supposed to show.

**It may be `known-incompat`, chosen.** FPC's Comp is a legacy Turbo Pascal
artefact — an integer that renders as a float. Someone writing `WriteLn(Co)`
almost certainly wants to see `5`, which is what we print; matching fpc here
means printing a *worse* answer to be identical. CLAUDE.md's ceiling is "ask
what the source MEANT, not what FPC returned", and what it meant is the number.

**What would settle it: real source that wants the scientific rendering** —
Comp used for its width and formatted for output. Absent that, a probe printing
a Comp is not evidence, the same way a program printing `SizeOf` of an
expression is not.

# Cost, if it turns out to be worth doing

Not a one-liner. `comp` would need its own `TTypeKind` rather than an alias, so
that the write path can branch on it, and every site that currently benefits
from Comp *being* Int64 (arithmetic, comparison, the rounding store fixed in
`3e2bca576`) would need to keep working through the new kind. Ranked 20 because
the value is already right and the shape is rare in real code — not because
nothing observably differs. Something does, on x86-64, measured.
