---
slug: bug-a-error-recovery-silences-every-lowering-only-diagnostic
track: A
prio: 45
status: done
owner: opus5-frank1
---

# Once ANY diagnostic is recovered, every lowering-only check stops firing

`519fa45a0` (feat(A), error-recovery slice 5) added to the top of `CompileAST`
in `compiler/ir_codegen.inc`:

    if ErrCount > 0 then Exit;

Correct on its own terms — do not lower an AST that already failed. The
consequence is not: **IR lowering stops at the first *recovered* diagnostic, so
every check that lives only in lowering becomes unreachable the moment anything
earlier in the file is reported.**

A recovered error is precisely the case where compilation *continues* in order
to report more. So this converts "report all the errors" into "report all the
errors the parser happens to own", silently, with no marker that anything was
skipped.

## How it surfaced

`test/test_indexing_length_for_new_inc_positive.pas` asserts eight refusals on
lines 44-51 and no binary. It got seven and a binary. Seven are parser checks
and survived; the eighth — `b := r < 1`, ordering a record with no `class
operator` — lived only in `ir.inc`'s binop lowering (`ir.inc:8746`).

Measured by Track P: it fires in isolation, and vanishes behind **any one** of
the five preceding recovered errors, whichever one it is.

Fixed for that case in `93c0ee76d` by moving the rule to where it belonged —
it is a Pascal *dialect* rule (its own `not CProgramMode` guard says so) and
was squatting in the shared IR, so it moved to the relational level in
`ParseExpr`. That fix is correct on its own merits and is **not** a fix for this
ticket.

## The hole that is left

At least two more diagnostics sit in the same `ir.inc` chain and are reachable
only through lowering:

- `no operator overload found for record operands` (arithmetic, `ir.inc:8721`)
- `arithmetic operator not supported for dynamic arrays` (the arm above it)

Neither is asserted *after* another diagnostic by any current test, so neither
is red today. Both are unreachable in exactly the situation a multi-error file
creates. **This is a silent hole, not a failing test** — which is this project's
most expensive defect class, and the reason it is filed rather than left in a
worker's report.

The test that caught the first one caught it by accident: it happened to assert
a lowering-only refusal *after* five parser refusals in one file. Nothing
systematically covers that shape.

## The actual question, which is a design call

**Where does error recovery draw the line between CHECKS and EMISSION?**

`ErrCount > 0 -> Exit` conflates them. Lowering does both: it runs semantic
checks that have no parser-level home, and it emits code. Only the second is
unsafe after an error.

Options, none free:

1. **Split the pass** — run lowering's checks, refuse to emit. Most correct;
   biggest change; needs every lowering site classified as check or emission.
2. **Move the checks out**, as `93c0ee76d` did for this one. Right answer where
   the rule is dialect-specific and the frontend can see enough to decide.
   Not general: some checks genuinely need lowered types.
3. **Guard the exit** — only bail once an *unrecoverable* error was seen.
   Cheapest, and closest to the intent the slice already had.

Related: `devdocs/dev/the-substrate-is-ast-and-ir-not-the-parser.md` (a dialect
rule in shared IR is a smell in itself) and
`devdocs/dev/normalise-dont-special-case.md` (two mechanisms — parser checks and
lowering checks — serving one concept, "reject this program", with different
survival rules under recovery).

## Not urgent, and why

The user already knows the file is broken; they get *fewer* errors, not a wrong
answer, and the binary case only arises alongside reported errors. Filed at 45
rather than urgent. But it should not be closed by fixing individual
diagnostics one at a time — that is the microfix, and the count of
lowering-only checks is the measure of how much is hidden.

*Banked by the Track P worker while fixing `regression-test-core-test-indexing-length-for-new-inc-positive`; filed by frank1-72.*

## Measurement banked, 2026-08-26 (opus5-frank1) — parked, not fixed

Confirmed the hole and sized the three options. **Option 3 is vacuous and option
1 is 619 call sites**, which reframes the ticket: only option 2 is reachable,
and only if the user-facing checks can be separated from the internal ones.

### The hole reproduces exactly as filed

```pascal
program e2;
type TR = record x: Integer; end;
var r, q: TR; n, u: Integer;
begin
  u := undefinedthing;   { recovered }
  n := r + q;            { lowering-only — silently not reported }
end.
```

Alone, `n := r + q` gives *no operator overload found for record operands*.
Behind one recovered error, only the first diagnostic is printed.

### Option 3 ("bail only once an UNRECOVERABLE error was seen") cannot work

`Error`/`ErrorAt` call `Halt(1)`. There is no unwinding, so an unrecoverable
error never *reaches* `CompileAST` — it ends the process where it is raised. By
the time `if ErrCount > 0 then Exit` is evaluated, every counted error is
recovered **by construction**. So option 3's guard is either always false (bail
never happens = the guard is removed = the original crash returns) or it is
today's behaviour. It is not a third option; it is option "revert".

### Option 1 ("split checks from emission") is 619 call sites

| file | fatal `Error(`/`ErrorAt(` | recoverable |
| --- | --- | --- |
| `ir.inc` | 123 | 1 |
| `ir_codegen.inc` | 100 | 0 |
| `ir_codegen386.inc` | 96 | — |
| `ir_codegen_riscv32.inc` | 87 | — |
| `ir_codegen_aarch64.inc` | 85 | — |
| `ir_codegen_arm32.inc` | 83 | — |
| `ir_codegen_xtensa.inc` | 45 | — |

Lowering cannot be run for its checks while any of those can fire, and there is
no exception to catch them with. Classifying all 619 is not a ticket, it is a
programme.

### Which reframes the ticket to a countable one

The 223 in `ir.inc`+`ir_codegen.inc` are overwhelmingly **internal
consistency assertions**, not user diagnostics — `invalid symbol in lea`,
`unknown IR opcode`, `invalid class index in vmtaddr`, `IR loop stack overflow`,
`<helper> not loaded`. Those firing on a poisoned AST is precisely what the
`ErrCount > 0 -> Exit` guard was added to prevent, and skipping them is right.

The ones that matter are the handful of **user-facing dialect rules** squatting
in shared IR, which is a smell on its own terms
(`the-substrate-is-ast-and-ir-not-the-parser.md`). `93c0ee76d` moved one out.
From the same sample, the remaining candidates are small and enumerable:

- `no operator overload found for record operands` (`ir.inc:8721`)
- `arithmetic operator not supported for dynamic arrays` (the arm above it)
- `case range: lower bound is greater than upper bound` (x2)
- `case of string: label must be a string constant` (x2)
- `case label does not match the ordinal selector type` (x2)

So the tractable shape is **option 2 applied to a list, not one at a time** —
which is what the ticket asks for when it says not to close this by fixing
individual diagnostics. The list above is that list, and the `case` rows suggest
the sweep should look for dialect rules generally, not only operator ones.

Parked here rather than half-done: the next worker starts from a sized problem
instead of a design question. Repro above is a two-minute check that it is still
live.

## Outcome — 2026-08-27

Option 2, applied to **the whole list at once** — which is what the ticket asks
for when it says not to close this by fixing individual diagnostics. All six
user-facing dialect rules the 2026-08-26 measurement enumerated now run in the
Pascal frontend, recovering, and every one of them survives an earlier recovered
diagnostic. The lowering keeps its own call in each case, fatal, as the backstop.

### The list, closed

| rule | was | now |
| --- | --- | --- |
| `no operator overload found for record operands` | `ir.inc` binop lowering | `CheckArithOperandsHaveAMeaning`, tail of `ParseTerm` / `ParseSimpleExpr` |
| `arithmetic operator not supported for dynamic arrays` | same arm | same |
| `case range: lower bound is greater than upper bound` (x2) | `CaseLabelBounds` | `ValidateParsedCaseLabels`, tail of `ParseCaseStatementAST` |
| `case of string: label must be a string constant` (x2) | same | same |
| `case label does not match the ordinal selector type` (x2) | same | same |
| `duplicate or overlapping case label` | `IRValidateCaseLabels` | same |

That last row was not on the filed list and came along for free: it lives in the
same walker, so moving the walker moved it.

### Why the case rules could move at all

They read **nothing** the lowering computes. `CaseLabelBounds` and the pairwise
overlap walk are pure AST — `ASTKind`, `ASTIVal`, `ASTSOffset/ASTSLen` — and the
single thing the lowering knew that the parser did not is whether the SELECTOR
is a string. So the walker moved to `ast_arena.inc` (language-agnostic, included
before every frontend and before `ir.inc`) and the *selector classification*
stayed at each caller, which is the only part that legitimately differs.

`ValidateParsedCaseLabels` is deliberately conservative about that one question:
it classifies only the tags that settle it the same way the lowering's
`IRTk in [tyString, tyAnsiString]` test would, and leaves an unresolved tag, a
frozen string kind, a variant or an auto to the backstop. A wrong `isStr` answer
would refuse labels that are in fact fine, on every case statement that
compiles — much worse than a missed diagnostic, which the backstop still catches.

Two supporting shape changes:

- **`CaseLabelDiag(lab, msg, recover)`** — one dispatcher, so the same rule is
  fatal from the lowering and recovering from the parser without a mode flag.
  It reports against `ASTLine[lab]`, the label's own line. The old `Error(msg)`
  used `CurTok`, which at lowering time is past the end of the file; the
  positions in the table below are new information, not just surviving ones.
- **`CaseLabelBounds` returns a Boolean** — a refused label has no interval, so
  under recovery the overlap walk must skip it rather than compare the garbage
  `ASTIVal` of a string node. Only reachable when `recover` is true; a fatal
  caller never returns from `CaseLabelDiag`.

### Measured

`test/test_diags_survive_error_recovery_fail.pas` (wired into `test-core`, two
invocations). One file, one recovered parser diagnostic on line 27, then six
lowering-owned refusals after it. **Before this change the file reported exactly
one error and the rest were silent.**

```
pascal26:27: error: undefined variable (undefinedthing)
pascal26:28: error: no operator overload found for record operands (...)
pascal26:29: error: arithmetic operator not supported for dynamic arrays (...)
pascal26:31: error: case label does not match the ordinal selector type
pascal26:35: error: case of string: label must be a string constant
--strict-case adds:
pascal26:38: error: case range: lower bound is greater than upper bound
pascal26:40: error: duplicate or overlapping case label
```

No binary in either run. The healthy control — ordinal and string `case` with
ranges and an `else`, under `--strict-case` — still compiles and runs.

This is the shape the ticket says *"nothing systematically covers"*: a
lowering-owned refusal asserted AFTER an earlier recovered one. It is covered now.

### What is deliberately NOT closed

`ErrCount > 0 -> Exit` stays. The 2026-08-26 count stands: option 1 is 619 sites
and option 3 is "revert". The 223 checks in `ir.inc` + `ir_codegen.inc` are
overwhelmingly internal consistency assertions — `unknown IR opcode`, `invalid
symbol in lea` — and skipping those on a poisoned AST is exactly what the guard
is for. What is fixed is the enumerable set of **user-facing dialect rules that
were squatting in shared IR**, which was a smell on its own terms
(`the-substrate-is-ast-and-ir-not-the-parser.md`). If another one is added there
later, this ticket's test is the shape that will catch it.

### Gate

`make compiler/pascal26` byte-identical (267f769b05bd) · `tools/gate.sh quick`
GREEN · pascal-conformance 346/0/170/34 · c-conformance 220/0 · fgl 7/7.

## Log
- 2026-08-27 — resolved, commit a69f55fb7.
