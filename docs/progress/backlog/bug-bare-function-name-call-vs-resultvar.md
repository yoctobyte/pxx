# Bare function name in an expression: PXX calls it, FPC/ISO reads the result var

- **Type:** bug (language semantics / FPC-compat) + self-host-vs-seed gotcha
- **Status:** backlog
- **Owner:** — (Track A)
- **Opened:** 2026-06-21
- **Relation:** surfaced while implementing feature-const-eval-typecast-int64.
  Companion to [[feature-fpc-vs-pxx-feature-boundary]].

## The divergence

Inside a function `F`, a bare `F` used in an **expression** (RHS of an
assignment, an argument, etc.) means two different things:

- **Standard Pascal / FPC (default fpc/tp mode):** bare `F` is the **result
  variable** of the function being defined — read its current value. To make a
  recursive call you must write `F()`.
- **PXX (self-host):** bare `F` is a **recursive call**.

These are opposite. PXX is the non-standard one.

```pascal
function ConstEval: Int64;
begin
  ...
  r := ConstEval;     { PXX: recursive call. FPC: read the result var. }
  r := ConstEval();   { both: recursive call }
end;
```

## Why it bit (and why it is subtle)

The compiler's own `ConstEval` (parser.inc, the `tkLParen` `(expr)` branch)
writes bare `r := ConstEval` and *relies on PXX calling it*. Consequences:

- The **FPC-built seed** (`fpc … compiler.pas`, e.g. `/tmp/pxx-build`) compiles
  that line as a result-var read, so its `ConstEval` mis-evaluates any
  parenthesised const expression — `const X = (5);` fails, `(1 shl 40) - 1`
  fails, etc.
- The **self-hosted** `compiler/pascal26` (built by a PXX binary) compiles the
  same line as a call, so it works.

So the FPC seed is **not a faithful oracle** for this corner of PXX semantics. A
change validated only on the FPC-built binary can look broken (or pass) and
behave the opposite way on the real self-hosted compiler. The bootstrap still
converges because `compiler/compiler.pas`'s own const expressions do not hit the
seed's broken path in a value-affecting way; `cmp build == verify` is between two
PXX-built binaries, both using the PXX (call) semantics.

## Repro

```pascal
program r;
const X = (5);     { fails on an FPC-built pascal26, works on the self-hosted one }
begin writeln(X); end.
```
Build one pascal26 with FPC directly and one via `make bootstrap`; compile the
above with each.

## Decision needed / fix direction

Pick the intended semantics (this is an FPC-compat call):

- **(a) Make PXX match FPC/ISO:** a bare function identifier in an expression is
  the result variable; require `F()` for a recursive call. This is the standard
  and what `feature-mimic-fpc` wants, but it is a behaviour change — audit every
  `r := SomeFunc` (bare) recursion site in the compiler source first (they would
  all need `()`), then flip. Risk: a missed site silently reads a result var.
- **(b) Keep PXX's "bare = call" and document it** as a deliberate dialect
  divergence (cheap, but a permanent FPC-source-compat wart: any imported FPC
  source using `Result`-style bare-name reads would miscompile).

Recommendation: (a) eventually (correctness + mimic), but it is a careful,
audited flip — not a quick change.

## Interim rule (already in practice)

- Always write `F()` with parens for a recursive/forward call in compiler source.
- **Validate any new recursion/helper on the self-hosted `compiler/pascal26`
  after `make bootstrap`, never on the FPC-built seed binary.**

## Sibling gotcha (same "seed is lenient" family)

Self-host requires **declaration-before-use**; FPC resolves the whole unit. A
helper near the top of `parser.inc` that calls `LowerCase` (defined far later)
compiles under FPC but fails self-host with `undefined variable (LowerCase)`.
Use an early-defined equivalent (`CaseEqual`, in `defs.inc`) instead. Worth a
one-line note here so the two "FPC seed masks it" traps live together.

## Log
- 2026-06-21 — filed (Track A). Both traps cost a bootstrap cycle during
  feature-const-eval-typecast-int64; the fix there used `ConstEval()` + `CaseEqual`.
