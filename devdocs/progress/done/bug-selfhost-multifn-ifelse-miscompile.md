# Self-host miscompilation: 3-function program with `if`/`else if` gives wrong result

- **Type:** bug — Track A / Track R (joint)
- **Status:** DONE 2026-07-04 — Track R trigger fixed (rparser.inc:609
  `RParseIf()`, on master) + Track A hardening delivered (`--strict-ir` guard)
  + regression gate in `make test` (`test/test_rust_else_if.rs`)
- **Owner:** Track A (finished the ownerless Track A half)
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

## ROOT CAUSE FOUND — 2026-07-04 (Track A investigation)

Reproduced read-only from `~/frank2` source built to /tmp (FPC-built frank2 → 20
correct; PXX-built/self-hosted → **1** wrong; ticket said 2 — same class, wrong
either way). Then narrowed with the `-S` disassembler + `--dump-ir`:

**1. NOT the general if/else-if shape (ticket's frontend-agnostic hypothesis
REFUTED).** The *identical* repro shape written in **Pascal** (`exit(n)` per
branch) AND in **C** (`int main(){...return total;}`, `f1` uncalled, `classify`
called) compiles **correctly and byte-identically** under both FPC-built and
PXX-built `pascal26`. So the shared if/else-if / call / return codegen is fine.
The trigger is specific to the **Rust frontend's IR shape**.

**2. The trigger: the Rust frontend mis-lowers `else if`.** `--dump-ir` of
`classify` (via frank2) shows the first `if`'s **else-branch lowered to an
`IR_UNSUPPORTED` node** (sitting between the else-label and the merge-label),
and the `else if` chain emitted *after* the merge label instead of nested inside
the else. So `classify(1)`: `n==0`? no → jump to the else-label → lands on the
`IR_UNSUPPORTED` node.

**3. The divergence: `IR_UNSUPPORTED` is handled nondeterministically across
self-host.** `IR_UNSUPPORTED` has NO codegen case in `ir_codegen.inc` (neither
master nor frank2). As an unreferenced value node it *should* never be emitted:
- **FPC-built** compiler: emits nothing there → control falls through the
  else-label to the merge-label → the `n==1` check runs → returns 20 (correct).
- **PXX-built** compiler: emits a spurious 5-instr block
  (`movsxd rax,[rbp-4]; mov [rbp-8],eax; movsxd rax,[rbp-8]; leave; ret` =
  "return n") AT the else-label → `classify(1)` returns `n=1` (wrong).
Confirmed in the `-S` diff: the else-label (`je` target) points at the spurious
block in the PXX build, at the real else-if in the FPC build.

## Fix ownership (two distinct fixes)

- **Track R (rparser, the real trigger):** `else if` must lower into the first
  `if`'s ELSE branch (a nested `if`), NOT emit `IR_UNSUPPORTED` + a flattened
  post-merge chain. Fixing this removes the trigger entirely — the highest
  priority, and it's in the Rust work being merged now.
- **Track A (self-host-safety hardening, independent):** `IR_UNSUPPORTED`
  reaching codegen currently yields *nondeterministic output* across self-host
  instead of a hard error. Codegen (`IREmitNode` + the driver loop) should
  **hard-error on `IR_UNSUPPORTED`** so any frontend that emits it fails LOUDLY
  at compile time rather than silently miscompiling. This would have caught the
  bug the instant Track R's frontend emitted the node. Worth landing regardless
  of the Rust fix — a general self-host guard. (Note: an unreferenced value node
  is never visited by the top-level driver, so the guard must also cover the
  case where such a node's presence perturbs label positioning — the precise
  PXX-vs-FPC emission mechanism for the spurious block was not fully isolated;
  the trigger + fix direction are solid.)

## Log
- 2026-07-04 — **Track R: fixed.** Root cause per Track A's investigation
  below was exactly right: `RParseIf` in `rparser.inc` built `elseNode :=
  RParseIf` (no parentheses) for the `else if` case. Inside a Pascal
  function's own body, its bare name (no parens) is the implicit
  `Result`-alias pseudo-variable, not a recursive call — so this read
  whatever garbage happened to be in that slot instead of actually
  recursing, and the "else" branch of the AST silently held an
  uninitialized/stale node index (`ASTKind` = `AN_NONE`), which is exactly
  what `IRLowerAST`'s fallback turns into `IR_UNSUPPORTED`. Confirmed via
  `--dump-ir` before/after: the `unsupported` instruction at the
  else-label is gone, `classify(1)` now returns 20 under `--dump-ir`
  disassembly, and — the real test — **the self-hosted `pascal26` now
  matches the FPC-built one** on the original repro (`t1.rs` → 40 under
  both). Fixed by adding parens: `elseNode := RParseIf()`, matching
  `pyparser.inc`'s `PyParseIf()` precedent (which always had them).
  Verified: `make bootstrap` stays byte-identical; `make -k test` green
  except the one pre-existing unrelated environment failure; all Track R
  sub-ticket 1-3 test programs re-verified against both the FPC-built and
  now-correct self-hosted compiler. Track A's `IR_UNSUPPORTED`-hardening
  idea (see "Fix ownership" above) is still open and independent — worth
  landing regardless, as a general self-host safety net, but no longer
  blocking anything since the trigger is gone.
- 2026-07-04 — Track A: reproduced (frank2→/tmp, read-only), refuted the
  general-shape hypothesis (Pascal+C correct+byte-identical), root-caused to the
  Rust frontend lowering `else if` to `IR_UNSUPPORTED` + codegen's
  nondeterministic handling of it. Handed to Track R (trigger) + flagged the
  Track A `IR_UNSUPPORTED`-should-hard-error hardening. No code changed (Rust
  work mid-merge).
- 2026-07-03 — filed from Track R sub-ticket 1/2 validation. Minimal repro
  above, several hypotheses ruled out (see "What's been ruled out"). Not
  self-resolved: this is shared `symtab.inc`/`ir.inc`/`ir_codegen.inc`
  territory with other Track A work concurrently landing on `master`, and
  root-causing further needs disassembly-level self-host debugging beyond
  what was practical while also carrying Track R's own sub-tickets.

## CLOSED — 2026-07-04 (Track A finished the ownerless half)

Both halves are now on `master` and verified together:

1. **Track R trigger (already merged):** `rparser.inc:609` reads
   `elseNode := RParseIf()` — parens present, with the own-name-Result-pseudo-var
   landmine documented inline. Confirmed on master, not just frank2.
2. **Track A hardening (landed 2026-07-04, commit 77e2fbd7):** the opt-in
   `--strict-ir` guard — `IRVerify` hard-errors on any `IR_UNSUPPORTED` node
   (referenced OR dead), turning "frontend gap → silent nondeterministic
   self-host miscompile" into an immediate compile error naming the AST kind.
   This is the general safety net that would have caught the dead node the
   instant rparser emitted it. Default OFF (Track R rust frontend still in dev);
   flip-to-default tracked in [[feature-selfhost-guard-ir-unsupported]].

**Regression gate (the acceptance item):** `test/test_rust_else_if.rs` — the
exact ticket repro (3 fns, one if/else-if/else-return chain, a call) — wired
into `make test` (`test-core`), asserted to **exit 20** both plain and under
`--strict-ir` (the latter also proves rparser no longer emits `IR_UNSUPPORTED`
here). This is the repo's **first rust-frontend gate in `make test`** — master
carried the rust frontend with zero make-test coverage until now. Verified on
the self-hosted `pascal26`: exit 20 (was 1/2 wrong before the rparser fix).

The ticket's "is this Rust-specific?" thread resolved to YES (Track A's
2026-07-04 investigation: the identical shape in Pascal and C compiled correctly
and byte-identically) — so a `.pas`/`.c` regression can't reproduce it; the `.rs`
gate is the right and only faithful regression.
