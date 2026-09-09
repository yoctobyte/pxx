---
track: P
prio: 45
type: bug
blocked-by: []
status: open
owner: ""
created: 2026-09-08
summary: "CORRECTED 2026-09-09 BY MEASUREMENT -- THE PREMISE BELOW WAS FALSE AND THIS IS NOT A GENERICS DEFECT. The old summary said the helper `applies to an ordinary non-generic call in that unit -- it is the substituted body that misses it`. It does not: a plain non-generic `TTest.Test` added INSIDE ugenfunc19 answers 1 against fpc 2, with no generics in the row at all. Measured at 0f14028acc04, five rows: gen-TTest 1/2, gen-TTest2 3/3, inunit 1/2, plain-TTest 1/2, plain-TTest2 3/4 (pxx/fpc). The boundary, one class and one helper across three member shapes: `class function static` 1/2, `class function` non-static 10/20, INSTANCE method 200/200. So class-helper instance methods dispatch correctly and CLASS-LEVEL helper methods are never applied at all, static or not -- the defect is helper dispatch through `TClass.Method`, not specialization scope and not `static`. AND THE SECOND ROW IS CORRECT BY ACCIDENT: pxx answers gen-TTest2 = 3 because it applies no helper anywhere, not because it correctly excludes the specializing program's helper -- rows 3-5 prove there is no exclusion rule to work. A dispatch fix WILL flip that row to 4, so it needs its own assertion first or the fix will look like it caused a regression it only revealed. fpc gives plain-TTest2 = 4 and gen-TTest2 = 3 for the same class, helper and program, so fpc really does resolve a template body in the TEMPLATE's context (two-phase lookup) -- that generics question is real but only becomes MEASURABLE once helpers are applied at all."
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


## 2026-09-09 (frankS) — measured, and the premise above is false

frankZ proposed splitting this between helper dispatch and generics scope and
asked whether the framing held. It does not, and the measurement is cheap enough
that it should have been made before the ticket was written — mine was.

Adding a plain non-generic `TTest.Test` **inside ugenfunc19 itself**, alongside
the corpus rows, at compiler `0f14028acc04`:

| row | pxx | fpc |
| --- | ---: | ---: |
| `specialize DoTest<TTest>` | 1 | 2 |
| `specialize DoTest<TTest2>` | 3 | 3 |
| **`InUnitPlain` — plain `TTest.Test`, inside the unit** | **1** | **2** |
| `TTest.Test` from the program | 1 | 2 |
| `TTest2.Test` from the program | 3 | 4 |

Rows 3–5 contain no generics. The substituted body behaves exactly like
hand-written code, which is the one thing the old body said it did not do.

### The boundary — one class, one helper, three member shapes

| shape | pxx | fpc |
| --- | ---: | ---: |
| `class function CS: LongInt; static` | 1 | 2 |
| `class function CN: LongInt` | 10 | 20 |
| `function Inst: LongInt` (instance) | 200 | 200 |

**Instance helper methods dispatch. Class-level helper methods never do**, and
`static` is not the discriminator. The defect is helper lookup for a class-level
member reached through `TClass.Method`.

### Why the "already correct" row must not be trusted as a control

`gen-TTest2 = 3` matches fpc, and the old summary leaned on it to warn that a
fix must not widen helper lookup. The warning is right; the evidence was not.
pxx answers 3 because it applies **no helper in any scope** — rows 3–5 — so that
row cannot show that a template-vs-specializing-scope rule exists, and a dispatch
fix will flip it to 4 with nothing holding it. Assert it before changing
dispatch, or the fix will appear to cause a regression it merely revealed.

fpc answering **4** for `TTest2.Test` and **3** for `specialize DoTest<TTest2>`
— same class, same helper, same program — is the real evidence that fpc resolves
a template body in the TEMPLATE's declaration context. That generics question is
genuine, and it is not measurable until helpers are applied at all.

Handed to frankZ whole; the slug now names something this is not.
