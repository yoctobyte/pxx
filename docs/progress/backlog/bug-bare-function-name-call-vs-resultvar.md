# Bare function name in an expression: PXX calls it, FPC/ISO reads the result var

- **Type:** bug (language semantics / FPC-compat) + self-host-vs-seed gotcha
- **Status:** backlog
- **Owner:** — (Track A)
- **Opened:** 2026-06-21
- **Relation:** surfaced while implementing feature-const-eval-typecast-int64.
  Companion to [[feature-fpc-vs-pxx-feature-boundary]].

## The divergence

Inside a function `F`'s own body, a bare `F` used in an **expression** (RHS of an
assignment, an argument, etc.) means:

- **FPC — verified in BOTH default (mode fpc) AND `-Mobjfpc`:** bare `F` is the
  **result variable** of the function being defined (read its current value). To
  recurse you must write `F()`.
- **PXX (self-host):** bare `F` is a **recursive call**.

These are opposite. PXX is the non-standard one.

**NOT a mode mismatch (tested 2026-06-21).** `function F: Integer; begin if calls<3 then F := F else F := 42; end;` prints `F=0 calls=1`
under *both* `fpc` (default) and `fpc -Mobjfpc` — i.e. `F := F` reads the result
var, no recursion, in every FPC mode. So building the seed with `-Mobjfpc` does
NOT align FPC with PXX; this is a genuine PXX semantic bug, not a build-flag fix.
(Outside its own body, `x := F` *does* call F in all modes — bare-name-is-result-
var is specific to reads inside the function's own scope.)

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

## Related `@` (proc-pointer) rule — verified, for the same bare-name model

`@` is the third meaning of a bare function name. Tested 2026-06-21:

- `p := @F` (proc-typed `p`) works in all modes.
- `p := F` (no `@`) — **default mode and `-Mobjfpc`: ERROR** ("Incompatible
  types: got LongInt …", i.e. it CALLED F); **`-Mdelphi`: works** (auto-takes the
  pointer).

So in our target (modern FPC, objfpc-ish), `@` is **required** for a procedural
pointer; only Delphi mode makes it optional. PXX already handles `@proc`
([[project_procedural_types_arc]]); audit that PXX does not silently accept a
bare `F` where `@F` is meant. The clean three-way model PXX should adopt:
`F`/`F()` = call (result var inside own body), `@F` = pointer, `Result` = result var.

## Decision needed / fix direction

This is a genuine PXX bug (FPC is consistent across modes), so the fix is one-way:

- **Make PXX match FPC:** a bare function identifier *inside its own body* is the
  result variable; require `F()` for a recursive call (and `@F` for a pointer).
  Behaviour change — **audit every bare-name recursion site in the compiler
  source first** (they must become `F()`), then flip. The known one is
  `parser.inc` ConstEval `tkLParen` branch (`r := ConstEval` → `r := ConstEval()`);
  there are likely others. Risk: a missed site silently reads a result var after
  the flip, so do the audit before, not after.

`-Mobjfpc` on the seed is NOT a fix (see above). Eventually wanted for
correctness + `feature-mimic-fpc`, but it is a careful, audited flip.

## Interim rule (already in practice)

- Always write `F()` with parens for a recursive/forward call in compiler source.
- **Validate any new recursion/helper on the self-hosted `compiler/pascal26`
  after `make bootstrap`, never on the FPC-built seed binary.**

## Sibling gotcha (split into its own ticket)

Self-host requires **declaration-before-use**; FPC resolves the whole unit (the
`LowerCase`-used-before-its-definition trap). Principled fix tracked separately:
[[feature-declaration-prescan]] (a header pre-scan, not lazy-linking). Interim:
use an early-defined equivalent (`CaseEqual` in `defs.inc`) / order callees first.

## Log
- 2026-06-21 — filed (Track A). Both traps cost a bootstrap cycle during
  feature-const-eval-typecast-int64; the fix there used `ConstEval()` + `CaseEqual`.
