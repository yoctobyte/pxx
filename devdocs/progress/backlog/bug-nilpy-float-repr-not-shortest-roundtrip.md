---
track: N
prio: 70
type: bug
---

# NilPy float repr is fixed-precision, not CPython's shortest round-trip

- **Type:** bug (NilPy output fidelity — silently WRONG-LOOKING and, in one
  direction, actively misleading) — **Track N**
- **Found:** 2026-08-01 while writing the regression test for
  [[bug-nilpy-typed-const-import-reads-zero]]; the test had to route around it.

## Measured (self-hosted binary at `a9edb6fba`)

| expression | pxx | CPython |
| --- | --- | --- |
| `print(25.4)` | `25.399999999999999` | `25.4` |
| `print(1/3)` | `0.333333333333333` | `0.3333333333333333` |
| `print(0.1 + 0.2)` | `0.3` | `0.30000000000000004` |
| `print(0.1)` | `0.1` | `0.1` |
| `print(2.5 * 2)` | `5.0` | `5.0` |
| `print(round(3.14159265, 3))` | `3.142` | `3.142` |

So it is not uniformly broken — it looks like fixed ~15-significant-digit
formatting where CPython uses `repr`'s **shortest string that round-trips**.

## Why it matters, and which direction is worse

Two distinct failures, and they point opposite ways:

1. **Too few digits — `0.1 + 0.2` printing `0.3`.** This is the dangerous one.
   CPython deliberately SHOWS the floating-point artifact; pxx hides it. Anyone
   using NilPy to reason about float behaviour is told the wrong thing, and the
   output looks *more* correct than reality. It also silently disagrees with the
   oracle in any diff-against-CPython test.
2. **Too many digits — `25.4` printing `25.399999999999999`.** Cosmetic by
   comparison, but it makes every float-bearing expected-output ugly, invites
   tests to bake in the wrong literal, and `1/3` losing its 16th digit means a
   printed value does not round-trip.

Any `.npy` test whose expectation contains a computed float is exposed, which is
also why this is worth fixing before more such tests are written.

## Fix shape (to determine — measure first)

CPython's `repr(float)` is the shortest decimal string that round-trips to the
same double (David Gay / Grisu / Ryu style). The likely home is NilPy's float →
string path (`pystr_of` / the float formatting in `compiler/builtin/pylib.pas`),
not the Pascal `Str`/`writeln` formatting, which has its own separate
contract and must not be changed to match Python.

**Check first whether Pascal's own float output is a shared code path** — if it
is, this needs a NilPy-only entry point rather than a change in place, or every
Pascal program's `writeln(x)` shifts too. That distinction is the whole risk of
this ticket.

A correct shortest-round-trip implementation is the real fix; a "print 17
digits then trim trailing zeros" approximation gets `0.1` wrong and must not be
substituted for it.

## Gate

A `.npy` diffed against CPython covering: `0.1 + 0.2`, `1/3`, `25.4`, `0.1`,
integral floats (`5.0`), very large and very small magnitudes, negative zero,
and `inf`/`nan` spellings. Plus confirmation that Pascal's own `writeln` of a
Double is unchanged.
