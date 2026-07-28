---
summary: "cfront: a file-scope global in a .c compiled as a UNIT is never reserved — arrays fail to lower, scalars silently read 0"
type: bug
track: C
prio: 70
---

# cfront: file-scope globals are unregistered when the `.c` is a UNIT

- **Type:** bug (C frontend, unit path) — **Track C**
- **Status:** done
- **Found:** 2026-07-28, probing AndreRenaud/pdfgen as the PDF backend for
  [[feature-demo-songformatter-pxx-target]]. A demanding consumer again.

## Symptom

The same C file compiles correctly as a PROGRAM and wrongly as a UNIT.

`carr.c`
```c
static int bins[] = { 1, 2, 4, 8 };
int pick(int i) { return bins[i]; }
```

As a C program (`bins[2]` printed from `main`) it prints `4`. Pulled from Pascal
with `uses carr` it does not compile:

```
warning: undeclared identifier 'bins' used as value (treated as 0)
error: IR_UNSUPPORTED: frontend could not lower AST node (kind 1) — a frontend gap, would miscompile
```

**The scalar case is worse, because it compiles.** With `static int base = 7;`
and `return base + i;`, `pick(2)` returns **2**: the global read silently becomes
a 0, so the answer is wrong with nothing but a warning. Silent wrong behavior.

Neither `static` nor the inferred array size matters — a plain
`int bins[4] = {...}` fails the same way. The distinction is program vs unit.

## Root cause (located)

`ParseCProgram` (`compiler/cparser.inc:7680`) runs two passes and splits top-level
declarations:

```pascal
    else if IsCTypeTok then
    begin
      if CTopLevelIsFunc then ParseCSubroutine
      else ParseCGlobalVarDecl;
    end
```

`ParseCUnit` (`cparser.inc:10365`) has neither. It is a single pass and its only
`IsCTypeTok` action is `ParseCSubroutine`, so a global declaration is walked as if
it were a function and no storage is ever reserved. It also has no pass 1, so a
function used before its definition inside the unit has nothing to resolve
against — which real C files (pdfgen among them) rely on.

## Fix

Give `ParseCUnit` the same shape as `ParseCProgram`: pass 1 under `CHeaderMode`
registering every signature and reserving every global, then pass 2 compiling the
bodies, with the func/global split in both.

## Acceptance

- The repro above, as a Pascal-used C unit, prints `4` — and the scalar variant
  prints `9`, not `2`.
- A C-unit regression test with a global array, a global scalar and a
  forward-referenced static function, wired into `make test`.
- pdfgen (5545 lines) compiles as a unit.

## Relation

Blocks the pdfgen backend, hence [[feature-lib-pxxpdf-reportlab-compat]] and
[[feature-demo-songformatter-pxx-target]]. Sibling of the (already fixed)
`bug-cfront-fegetround-unresolved-float-printf`, which came from the same probe.

## Log
- 2026-07-28 — resolved, commit 4bc0c13dc.

## Resolution

Fixed by 4bc0c13dc ("fix(cfront): a .c compiled as a UNIT gets the C-program
treatment"). The ticket was left in `backlog/` by that commit.

Re-verified 2026-07-28 on this ticket's own repro, both halves: `pick(2)` over
a file-scope `static int bins[]` returns 4 (it used to fail to lower), and the
scalar case `base + i` returns 9 rather than silently reading the global as 0.
