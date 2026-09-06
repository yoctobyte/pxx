---
track: P
prio: 62
type: bug
blocked-by: []
summary: "A bare parameterless METHOD passed as an argument to a call on a QUALIFIED receiver was `undefined variable`, while every other spelling of the same call compiled — `q := Cur`, `Own(Cur)`, `Free1(Cur)`, `Cur.Row`, `FE.MC(Self.Cur)`. Found as rung 7's wall in fcl-passrc `pparser.pp` (`Engine.CreateElement(..., CurSourcePos, ...)`), 3 of the unit's 5 remaining errors. FIXED: ByRefArgStartsExpression now recognises the METHOD spelling of a parameterless callee name, and ParamBindsAnExpression asks `const` instead of enumerating const TYPES one defect at a time."
status: done
---

# A parameterless method is `undefined variable` as a by-ref argument

- **Type:** bug (Pascal frontend) — **Track P**.
- **Found:** 2026-09-06 by frankD, as the `pparser.pp` wall of
  [[feature-pascal-corpus-expansion]] rung 7 (fcl-passrc).
- **Fixed the same session.** Filed in `done/` because the source comments and
  two fixtures cite the slug, not because it needed coordination.

## The bug

```pascal
FE.MC(Cur);          { undefined variable (Cur) }
```

where `Cur` is a parameterless `function` method of the ENCLOSING class and
`MC` takes `const p: TRec`. Measured boundary — everything else compiled:

| spelling | result |
| --- | --- |
| `q := Cur` | OK |
| `Own(Cur)` — argument to an own unqualified method | OK |
| `Free1(Cur)` — argument to a free routine | OK |
| `Cur.Row` — field of the bare result | OK |
| `FE.MC(Self.Cur)` — explicit Self | OK |
| `FE.MC(Add(A, B))` — a call EXPRESSION | OK |
| `FE.MVal(CurI)` — by-VALUE parameter | OK |
| **`FE.MC(Cur)`** | **`undefined variable (Cur)`** |
| **`FE.MTwo(1, Cur)`** | **same, any position** |

So the affected door is exactly **the argument list of a call on a qualified
receiver, at a by-ref parameter** — the one path with no implicit-Self arm
anywhere on it.

## Mechanism

`ByRefArgStartsExpression` (`pasparser_call.inc`) decides whether a by-ref
argument may be an expression or must be a bare lvalue. Answering False forces
`ParseLValueAST(FindSym(name), …)`, and `FindSym` of a method name is -1, so
the argument came out as an undefined variable. Two independent reasons it
answered False here:

1. **The callee-name lookup was free-functions-only.** The clause that already
   recognises a bare parameterless FUNCTION (`FindProc`) has no method
   spelling, so a method name missed both lookups.
2. **The gate enumerated const TYPES.** `ParamBindsAnExpression` was
   `const Variant` OR `const array of T`. A `const <record>` is by-ref because
   a record is and const because it is written const, and it was in neither
   arm.

## Fix

Two edits, both in `compiler/pasparser_call.inc`:

- `ParamBindsAnExpression` now asks **`const`**, which is the rule the two
  enumerated arms were spelling out. A `const` parameter takes a VALUE; the
  by-ref transport under it is an ABI decision the language does not expose.
  `var`, `out` and untyped are unchanged, which is the half that matters.
- The bare-name clause in `ByRefArgStartsExpression` gained the METHOD lookup
  beside the free-function one, via `SelfMemberCi` + `FindUMeth` (Self is
  `Params[0]`, so parameterless is `ParamCount = 1`).

**Why not a third implicit-Self arm.** `ParseFactorCore` has one and
`ParseLValueAST`'s unresolved-name path has none, and the note-to-self on the
corpus ticket said to mirror rather than add a third — *two entries are why
[the sibling] bug survived one fix*. Routing the argument to `ParseExpr`
instead reuses the arm that already exists, so the count of implicit-Self
dispatchers does not go up.

## Measured

- Reduced 8-cell matrix and the corpus unit, both byte-identical to
  **fpc 3.2.2**.
- Rung 7 `pparser.pp`: **5 errors → 2**. The three `undefined variable
  (CurSourcePos)` at `:7616/:7629/:7637` are gone. Baseline binary
  `3abc191e6313`, fixed binary `c16bfccded88`, same tree otherwise; the fixed
  binary reproduced the same sha across a revert/restore/rebuild cycle.
- `tools/gate.sh quick` **GREEN**, FPC seed canary included (the new code
  reaches `pasparser_lval.inc`-era helpers from `pasparser_call.inc`, which is
  included FIRST — `SelfMemberCi` and `FindUMeth` are both `symtab.inc`, so
  single-pass FPC is satisfied and the canary is the instrument that says so).
- Two new `test-core` rows, both GREEN through `testmgr --tier native`.

## The remaining rung-7 wall is NOT this

`pparser.pp:778` `raise ENotSupportedException.Create(SErrMultipleSourceFiles)`
— an RTL exception class `lib/rtl` does not declare. **Pre-existing**: it is in
the baseline's 5 errors too, and the compiler's `in:` line misattributes it to
`pscanner.pp`, which is this corpus's standing coordinate problem and not a new
one. Separate work, separate lane (B/RTL).

## Guards

- `test/test_paramless_method_as_const_byref_arg.pas` (+ `.expected`, fpc's own
  output). Carries a **precedence row that looks redundant**: `TFar` declares
  its own `Cur`, so a fix resolving the bare name on the RECEIVER passes every
  other row and prints 99 where fpc prints 7.
- `test/test_paramless_method_as_var_arg_refused.pas` — a genuine `var`
  parameter must still refuse. **Aimed**: the same file with `var` → `const`
  compiles and prints 5, so the refusal is about `var` and not about the
  fixture. Asserted as "does not compile" rather than on the message text; our
  wording is still `undefined variable`, which is wrong wording on a correct
  refusal and predates this fix.

Both cross-reference the free-function twins
([[bug-p-a-parameterless-function-is-undefined-as-a-method-call-argument]]),
and those two now cross-reference back.
