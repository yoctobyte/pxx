---
slug: bug-t-forward-decl-lint-counts-nested-functions-as-globals
track: T
prio: 45
type: bug
blocked-by: []
status: open
created: 2026-08-30
summary: "gate.sh's `fpc seed compiles (forward decls)` step treats a NESTED function's name as a global, so any later file using that name as a parameter, local or field is failed for calling something FPC has not seen. Measured: a parameter named argName failed against rparser.inc's ArgName, nested inside RResultClassForRec and invisible outside it. False positive, and it fails the gate."
---

# T: the forward-decl lint counts nested functions as globals

## What happened

`tools/gate.sh quick` step **`fpc seed compiles (forward decls)`** went RED on a
Track P change that had no forward-declaration problem:

```
FAIL compiler/pasparser_generic.inc:1437: calls argName, declared at
     compiler/rparser.inc:504, which FPC has not seen yet
```

`compiler/pasparser_generic.inc:1437` was:

```pascal
  if specArgKind = tkIdent then argCi := FindUClass(specArg);
```

...before renaming; the offending identifier `argName` was a **`const`
parameter** of the enclosing procedure, not a call.

And `rparser.inc:504` is a **nested** function:

```pascal
function RResultClassForRec(okTk: TTypeKind; okRec: Integer;
                            errTk: TTypeKind; errRec: Integer): Integer;
var name: AnsiString; ci, vi, payOff, align, endOff: Integer;

  function ArgName(tk: TTypeKind; rec: Integer): AnsiString;    { <-- nested }
  begin
```

`ArgName` is local to `RResultClassForRec` and unreachable from any other
routine, let alone another include. There is no FPC ordering hazard here in
either direction.

## Repro

Name a parameter, local variable or field in any `compiler/*.inc` after
`rparser.inc` in `compiler.pas`'s include order — `argName` will do — and run
`tools/gate.sh quick`. The step fails. Renaming the local makes it pass; the
compiler is unaffected either way (the self-host fixedpoint produced a
byte-identical binary across the rename, sha `9c8f23be1d4c` both sides, which is
the proof that nothing about the build changed).

## Why it matters

The lint guards something real — pxx resolves across the unit while FPC resolves
in source order, so a genuine missing `forward;` breaks the bootstrap seed — and
it is a **gate** step, so a false positive stops a lane. The cost is not just the
noise: the sanctioned workaround is to rename your own local, which means the
lint quietly reserves every nested function name in the tree as a global
identifier nobody may reuse. `ArgName`, `Emit`, `Flush` and friends are exactly
the names a nested helper gets.

## Fix

Skip function/procedure declarations that are nested inside another routine when
building the "declared globals" table — a nested declaration is indented inside
an enclosing routine's declaration part, between its header and its `begin`, and
is not addressable from outside it. Only top-level (column-0) declarations
belong in that table.

Filed by Track P per **T owns the tool, never the bug** — worked around locally
by renaming the parameter rather than editing Track T tooling. Found while
resolving [[bug-p-generic-type-constraints-are-parsed-and-discarded]].
