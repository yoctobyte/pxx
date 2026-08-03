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

## 2026-08-01 — investigated; BLOCKED on the RTL, and the shared-path risk is real

Both questions the ticket raised are now answered by measurement.

**1. Is Pascal's float output a shared path? YES.** `pystr_of(d: Double)` in
`compiler/builtin/pylib.pas` is literally `Result := FloatToStr(d)`. So this
must gain a NilPy-only entry point; changing `FloatToStr` in place would move
every Pascal program's `writeln` and a lot of expected output with it.

**2. Can shortest-round-trip be built on today's RTL? NO.**
`FloatToStrSig` caps at 15 significant digits by design
(`if sig > 15 then sig := 15; { past 15 a double scaled in doubles lies }`) —
it normalises by scaling in doubles, so further digits would be fiction. A
double needs up to 17 to round-trip. Probed with
`StrToFloat(FloatToStrSig(d, p)) = d` for p = 1..17:

| value | shortest p | at p=17 |
| --- | --- | --- |
| `25.4` | 3 (`25.4`) | — |
| `0.1` | 1 (`0.1`) | — |
| `0.1 + 0.2` | **never** | `0.3` |
| `1/3` | **never** | `0.333333333333333` |

So the exact values this ticket is about are precisely the ones the RTL cannot
express. **blocked-by:** [[bug-b-floattostrsig-caps-at-15-significant-digits]].

### A partial fix is possible and was deliberately NOT taken

A 1..15 round-trip loop would fix `25.4` (→ `25.4`) and leave the rest no worse.
Rejected for now on blast radius: float output changes ripple into every
expected-output that contains one, and it would still get the *dangerous* case
wrong — `0.1 + 0.2` would keep printing `0.3`, hiding the artifact CPython
shows, which is the half of this bug that actually misleads. Better to land it
once, correctly, after the RTL gains exact digits. Whoever picks this up can
revisit that call.

### Also needs handling on the NilPy side once unblocked

`FloatToStrSig` spells several things Pascal's way: `5.0`→`5`, `1.0e20`→`1E20`,
`-0.0`→`0`, `NaN`/`Inf`. Python needs `5.0`, `1e+20`, `-0.0`, `nan`/`inf`.


## 2026-08-02 — a SECOND consumer wants the same primitive

`round(x, n)` needs it too. CPython's `round` operates on the double's exact
decimal value, not on `x * 10**n`:

```
Decimal(2.675) = 2.674999999999999822...  -> round(2.675, 2) = 2.67
Decimal(2.665) = 2.665000000000000035...  -> round(2.665, 2) = 2.67
```

Both scale to exactly `267.5` / `266.5`, so the deciding information is gone
before any tie-break rule runs — see
[[bug-nilpy-round-ndigits-half-up-and-ignores-negative-ndigits]], where the
other two defects were fixed and these two cases documented as blocked.

Note a 17-significant-digit approximation does NOT suffice for round either:
`2.665` renders as exactly `2.6650000000000000`, which is ambiguous at the tie.
So both consumers need genuinely EXACT digit generation, not more digits.

Raising the value of [[bug-b-floattostrsig-caps-at-15-significant-digits]]
accordingly: it now unblocks two user-visible parity gaps, not one.


## 2026-08-02 — a THIRD symptom: no exponent form for small magnitudes

```python
print(1e-10)     # CPython 1e-10     pxx 0.0000000001
print(1e10)      # CPython 10000000000.0   pxx 10000000000.0   (agrees)
```

CPython's `repr` switches to exponent notation below `1e-4` and at/above
`1e16`; pxx renders fixed-point throughout. Same routine family as the
shortest-round-trip gap, so it should be settled in the same pass rather than
patched separately — the exponent threshold is part of the same "how does a
double print" contract.
