---
summary: "the constant evaluator was integer-only: an alias of a real const printed its IEEE bits as an integer, `: double = 3` stored 0.0, `= -3` stored Nan, and any real arithmetic in a const was a parse error"
type: bug
prio: 55
track: P
---

# Constant expressions were integer-only — four wrongs from one gap

- **Type:** bug (Pascal frontend, `compiler/parser.inc` const evaluator).
  Track P; the shared parser file makes it A's ground too (sole-A confirmed).
- **Status:** done
- **Found:** 2026-08-16, Pascal oracle sweep vs `fpc -O- -Mobjfpc` (typed
  constants topic).
- **Shape:** one concept (a constant whose value is real) reachable through
  several syntactic routes, with the evaluator modelling only the narrowest —
  `devdocs/dev/normalise-dont-special-case.md`.

## Symptoms

`ConstEval` evaluates over `Int64`, and a real const was recognised only as a
**bare literal token**, by looking at the FIRST token of the initializer.
Everything else fell to the integer evaluator:

| source | pxx | FPC |
| --- | --- | --- |
| `const A = 3.14; B = A;` -> `writeln(B)` | `4614253070214989087` | `3.14` |
| `const A: double = 3;` | `0.00` | `3.00` |
| `const A: double = -3;` | `Nan` | `-3.00` |
| `const A = 3.14 * 2;` | `error: unexpected token` | `6.28` |
| `const A = 6 / 3;` | `error` | `2.00` |
| `const A: array[0..1] of double = (1.5, 2.5*2);` | `error` | `5.00` |

The first three are **silent wrong values** — the integer sitting in the slot
is read back as IEEE bits (3 decodes to a denormal that prints 0.00, -3 to a
NaN). The last three are loud. `const TwoPi = Pi * 2;` is ordinary Pascal, so
the loud ones were the visible half of a gap whose quiet half was worse.

## Fix

A **parallel evaluator over `Double`** (`ConstEvalF` / `ConstEvalFTerm` /
`ConstEvalFFactor`), entered only when the expression is provably real:

- `ConstExprIsFloat` scans the initializer's tokens to its terminator at paren
  depth 0 and answers yes on a real literal, on `/` (real division yields a
  real even for integer operands), or on a bare name that already resolves to a
  real const. Conservative on purpose: a **no** leaves the integer path running
  exactly as before, which is what keeps every existing constant byte-identical.
- Anything the real evaluator does not model itself — `SizeOf`, `Ord`/`Chr`,
  an integer typecast, an enum member, a class or unit-qualified const — is by
  definition an integer factor, so it hands the same token to `ConstEvalFactor`
  and widens. Deliberately the FACTOR and not `ConstEval`: a whole expression
  would swallow the `* 2.5` that follows.
- `ParseInitValTk(tk)` for the call sites that know the destination type (they
  all had it in a local already): a real destination always yields IEEE bits,
  which is what fixes `: double = 3` and `= -3`.
- `ParseInitVal` lost its bare-literal-plus-sign special case entirely — the
  real evaluator covers it, so `= -2.5` and `= 2.5 * -1` cannot disagree.

## Gate

`make compiler/pascal26` fixedpoint; `tools/gate.sh quick` GREEN;
`test/test_const_real_expressions.pas` (alias, real*int, additive chain,
parens, negation, `/` on integers, `1e-9`, a real-typed array element
expression, plus the integer forms `2*3+1`, `1 shl 40`, `SizeOf(Integer)*2`
that must not move) matches `fpc -O- -Mobjfpc` byte for byte. `lib/rtl`'s
float-const-heavy units (`math`, `vecmath`, `ucomplex`, `sysutils`) still
compile and `Pi`, `Sqrt(2)`, `DegToRad(180)` are right.

## Not covered (deliberate)

`ConstExprIsFloat` resolves **bare** names only; a `unit.RealConst` qualifier
in a const expression still takes the integer path and its old behaviour.
Resolving units inside a lookahead is a bigger change than the payoff — file a
follow-up if a corpus ever hits it.
