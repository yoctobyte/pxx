---
track: P
prio: 45
type: bug
blocked-by: []
status: open
owner: ""
created: 2026-09-08
summary: "`generic function DoTest<T>: LongInt; begin Result := T.Test; end;` in a unit that also declares `TTestHelper = class helper for TTest` resolves `T.Test` to TTest's OWN class function and not to the helper's: pxx 1, fpc 2. The helper is declared in the SAME unit as the template, ten lines above it, and applies to an ordinary non-generic call in that unit — it is the substituted body that misses it. Uncovered 2026-09-08 when the splice-position defect in front of it was fixed (d1d78434de8c); PRE-EXISTING, proved by stash-and-rebuild at cd2d264c72df, which answers 1 for the same call without that change. tgenfunc19.pp is the corpus row and this is now its only wall: the file compiles and links and exits rc=1 on `if specialize DoTest<TTest> <> 2 then Halt(1)`. THE OTHER HALF IS ALREADY CORRECT and is the harder one: `DoTest<TTest2>`, where the program declares BOTH TTest2 and a TTest2Helper, answers 3 — the class's own method — which is what fpc answers, so a fix must not simply widen helper lookup at the specialization site or that row flips to 4."
---

# The shape

`library_candidates/fpc-testsuite/tests/test/ugenfunc19.pp`, unmodified:

```pascal
unit ugenfunc19;
type
  TTest = class class function Test: LongInt; static; end;
  TTestHelper = class helper for TTest class function Test: LongInt; static; end;
generic function DoTest<T: TTest>: LongInt;
implementation
class function TTest.Test: LongInt;       begin Result := 1; end;
class function TTestHelper.Test: LongInt; begin Result := 2; end;
generic function DoTest<T>; begin Result := T.Test; end;
end.
```

```
pxx   DoTest<TTest> = 1
fpc   DoTest<TTest> = 2
```

Both the class and its helper are declared in the template's OWN unit, above
the template. Nothing about the specializing program is involved in this row.

## Two rows, and they pull in opposite directions

Measured at `d1d78434de8c` with the program from `tgenfunc19.pp`:

| call | pxx | fpc 3.2.2 |
| --- | --- | --- |
| `specialize DoTest<TTest>` — helper in the TEMPLATE's unit | **1** | 2 |
| `specialize DoTest<TTest2>` — helper in the SPECIALIZING program | 3 | 3 |

**The second row is already right and is the constraint on any fix.** FPC binds
the body's names in the template's declaration context, so a `class helper`
written by the specializing program does not reach it. Widening helper lookup at
the specialization site would fix row 1 and break row 2 — and row 2 breaking is
the silent direction, since 4 is as plausible a number as 3.

So the question is not "are helpers applied" but "**which scope's** helpers", and
the answer is the template's unit, not the specialization's.

## Why it was invisible until today

The splice-position defect
(`bug-p-an-imported-generic-routine-is-spliced-before-the-programs-own-type-section`)
refused this file at `unknown type: TTest2` before any of it ran. That ticket's
skip reason for `tgenfunc19.pp` says the class-helper rule *"was already carved
out … and was never this row's wall"* — true about the wall being measured then,
and false as a claim about the file. **A wall behind a wall reads as no wall.**

## Corpus

`tgenfunc19.pp`, and it is now the file's ONLY remaining wall: it compiles,
links, and exits `rc=1` at `if specialize DoTest<TTest> <> 2 then Halt(1)`.
