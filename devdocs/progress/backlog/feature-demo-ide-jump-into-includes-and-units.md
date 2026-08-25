---
slug: feature-demo-ide-jump-into-includes-and-units
track: B
prio: 35
type: feature
blocked-by: []
summary: "garin's diagnostic parser keys off `a number between the first two colons` and carries no file, on the stated assumption that the compiler names one main unit. Since 2026-08-21 that is no longer true: a diagnostic in an include or a `uses`d unit is followed by an `in: <path>` line, which the IDE currently drops, so jump-to-error lands on the wrong file."
status: backlog
---

# The IDE cannot jump into an include or a unit

`apps/ide/garin/builder.pas` parses compiler output as
`<prefix>:<line>: <message>` and comments that *"the source file is the caller's
business (the compiler names one main unit)"*.

That assumption held until
`bug-a-a-parse-error-in-a-used-unit-reports-a-line-in-no-file`. The compiler now
emits, under a diagnostic whose token did not come from the main source:

```
pascal26:63: error: expected expression
  in: test/incdiag/badinc.inc
  near:  procedure Bogus  begin if >>> then  end
```

The line number is now a real line **of that file**, not of the main source — so
an IDE that keeps the number and drops the path jumps to line 63 of the wrong
file, which is worse than the old behaviour where the number was wrong in a way
nobody could act on.

## The ask

- `TDiagList` carries an optional file per diagnostic: a bare `  in: <path>`
  line attaches to the diagnostic above it.
- The faces (eliah's error list, ilja) open that file when jumping.
- `bochan/main.pas`'s canned sample output gains a case with an `in:` line so the
  rendering is exercised without a compile.

Deliberately NOT a compiler change: the `in:` line was put on its own line
precisely so the existing `<prefix>:<line>:` contract keeps working, and an IDE
that ignores it behaves exactly as it did before. This ticket is the upgrade,
not a repair.

## Gate

Track B: build with `$(PXX_STABLE)`, `make demos`. A diagnostic in an include
opens the include.
