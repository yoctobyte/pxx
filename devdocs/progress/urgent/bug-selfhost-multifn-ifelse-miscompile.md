# Self-host miscompilation: 3-function program with `if`/`else if` gives wrong result

- **Type:** bug — Track A
- **Status:** urgent
- **Owner:** —
- **Opened:** 2026-07-03 (found while validating Track R / Rust frontend
  sub-tickets 1-2, but the bug is in shared compiler internals, not the
  Rust frontend, and is not Rust-specific in principle — see below)

## Summary

`compiler/pascal26` built via the normal 3-stage `make bootstrap` (FPC →
PXX → PXX, byte-identical) gives a **different, wrong runtime result** than
the exact same source built directly by FPC, for the same input program.
The self-host fixedpoint (`make bootstrap`'s byte-identical check) does
**not** catch this — it only proves PXX-built-by-PXX is internally
consistent with itself, not that it matches FPC-built behavior. This is a
real, silent correctness bug: no crash, no error, just a wrong number.

## Minimal repro

```
fn f1(a: i32) -> i32 {
    return a;
}
fn classify(n: i32) -> i32 {
    if n == 0 {
        return 10;
    } else if n == 1 {
        return 20;
    } else {
        return 30;
    }
}
fn main() -> i32 {
    let mut total = 0;
    total = total + classify(1);
    return total;
}
```

(`.rs` extension via the Track R frontend, but see "Is this Rust-specific?"
below.) Expected exit code 20.

- FPC-built `pascal26`: **20** (correct).
- Self-hosted `pascal26` (3-stage bootstrap, byte-identical to itself):
  **2** (wrong).

## What's been ruled out

- Not a stale-binary artifact: reproduced after `rm compiler/pascal26` +
  clean `make bootstrap`.
- Not the newly-landed `-O1` imm-fold/DCE optimizer work (`ir_codegen.inc`,
  landed in `fb779d8`/`2890475`): reproduced identically self-hosting from
  the commit *before* that work landed, with the same Rust-frontend files.
  Also: default `OptLevel = 0` (no `-O` flag passed), so that optimizer
  pass shouldn't even run for this repro.
- Not a general self-host regression: the full `make -k test` suite (229
  C/Pascal/Python/asm programs) passes against the same self-hosted binary
  that gets this repro wrong. Existing multi-function C/Pascal programs
  with `if`/`else if` chains and forward calls are common and pass fine.
- Not about function *count* alone: 3 trivial one-line functions (no
  `if`/`else if`) self-host and run correctly. It specifically needs a
  function shaped like `classify` above (an `if`/`else if`/`else` chain
  with an early `return` per branch) *plus* at least one other declared
  function *plus* the call site, all three present. `classify` + `main`
  alone (2 functions, no `f1`) is correct. `f1` + `classify` (declared,
  *uncalled*) + `main` (calling only `f1`) is also correct — `f1` must be
  present and `classify` must be called for it to break.

## Is this Rust-frontend-specific?

Structurally it looks like a general call-fixup / codegen interaction bug
that any frontend generating this AST shape (3 procs, one with a
return-per-branch if/else-if chain, forward/plain calls between them)
could hit — it reproduces with zero Rust-only IR nodes (`AN_IF`/`AN_CALL`/
`AN_ASSIGN`/`AN_EXIT`, all shared). It just hasn't been caught before,
either because no existing Pascal/C/Nil-Python test happens to match this
exact shape, or because it's specifically about how `rparser.inc`'s own
source (new Pascal code) gets self-compiled — not yet isolated further; a
Track A investigation with `-g`/disassembly on the *self-hosted compiler
compiling itself* around `ApplyCallFixups`/`EmitProcPrologue`/`CompileAST`'s
`AN_IF` path is the natural next step, not something this ticket's author
attempted (would mean touching shared `symtab.inc`/`ir.inc`/`ir_codegen.inc`
concurrently with other Track A work already landing on `master`).

## Impact / how Track R is proceeding around it

Not blocking forward progress: Track R (Rust frontend, `~/frank2` branch
`feature/rust-frontend-skeleton`) validates sub-tickets against the
**FPC-built** compiler as the correctness oracle (confirmed correct on
every test in sub-tickets 1-2) and only uses the self-hosted
`make bootstrap` binary for the byte-identical-fixedpoint check, not as a
correctness reference, until this is fixed. Flagging this explicitly:
sub-ticket 1/2's "self-compiles to correct runtime output" claims are true
for the FPC-built compiler; the self-hosted compiler currently silently
gives wrong output for at least this input shape, discovered fortuitously
by Rust test programs but not caused by the Rust frontend's AST/IR usage
(all shared node kinds, already used elsewhere).

## Acceptance

- Root-cause identified (which shared function miscompiles under
  self-host for this shape).
- Fix lands with a regression test that fails on today's `master` self-host
  and passes after the fix (ideally as a `.c` or `.pas` program too, to
  confirm it's not Rust-specific).
- `make bootstrap` self-host stays byte-identical; the regression test's
  self-hosted output now matches its FPC-built output.

## Log
- 2026-07-03 — filed from Track R sub-ticket 1/2 validation. Minimal repro
  above, several hypotheses ruled out (see "What's been ruled out"). Not
  self-resolved: this is shared `symtab.inc`/`ir.inc`/`ir_codegen.inc`
  territory with other Track A work concurrently landing on `master`, and
  root-causing further needs disassembly-level self-host debugging beyond
  what was practical while also carrying Track R's own sub-tickets.
