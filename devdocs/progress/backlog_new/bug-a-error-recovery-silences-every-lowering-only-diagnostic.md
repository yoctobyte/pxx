---
slug: bug-a-error-recovery-silences-every-lowering-only-diagnostic
track: A
prio: 45
status: backlog_new
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
