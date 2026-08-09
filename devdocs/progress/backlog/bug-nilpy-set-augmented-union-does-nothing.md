---
prio: 50
track: N
type: bug
blocked-by: []
---

# `a |= <set>` silently does nothing (and mixing it with `+=` segfaults)

- **Type:** bug (NilPy, **silent wrong value**, and a crash in one shape) — **Track N**
- **Found:** 2026-08-09, running a realistic config-reader program against
  CPython. Not visible from an API sweep — it needs the augmented form, which
  no single-call probe uses.
- **Owner:** —

```python
a = set()
for i in [1, 2]:
    a |= set([i])
print(sorted(a))       # CPython [1, 2]     pxx []
```

The plain spelling is CORRECT:

```python
a = set()
for i in [1, 2]:
    a = a | set([i])   # [1, 2] on both
```

Two spellings of one operation answering differently is the tell this codebase
keeps recording.

## Measured

| shape | CPython | pxx |
| --- | --- | --- |
| `a |= set([i])` in a loop | `[1, 2]` | **`[]`** |
| `a |= set([9])` in a loop (constant RHS) | `[9]` | **`[]`** |
| `a = a | set([i])` in a loop | `[1, 2]` | `[1, 2]` |
| `d |= set([5])` with NO loop | `[5]` | `[5]` |
| the same file mixing `|=` with `b += [i]` and `c += i` | fine | **SEGFAULT** |

The last row matters: this is not only a lost update. A program that uses `|=`
beside ordinary `+=` accumulators crashes, which is how it first showed up.

## Cause

`PyAugBinTok` (pyparser.inc ~14881) maps the augmented token to its binary
partner, and `tkPipeEq` maps to **`tkOr`** — the general or-operator token. The
desugar then builds an `AN_BINOP` with `tkOr` DIRECTLY, so it never reaches
whatever the ordinary `|` path does for two SETS (which is why the plain
spelling is right: it goes through that path and lowers to the set-union
helper).

`tkAmpEq -> tkAnd` is the same shape and `&=` on sets should be checked in the
same pass; `^=` (`tkXorEq -> tkXor`) too.

## Shape of a fix

Make the augmented desugar go through the SAME operator lowering the plain
binary form uses, rather than hand-building an `AN_BINOP` — that is the
`normalise-dont-special-case` answer, and it fixes `&=`/`^=`/`-=` on sets at the
same time instead of one token at a time. If that is too large, the narrow
version is to route a set-typed (or variant) operand pair to the set helpers in
the desugar, but note that only moves the second path rather than removing it.

Check the SEGFAULT separately once the union works — it may simply be the same
wrong lowering meeting an accumulator of another type, or it may be its own
fault.

## Gate
`.npy` diffed against CPython: `|=` in a loop and outside one, with a constant
and a loop-dependent RHS, `&=` and `^=` on sets, `|=` on INTEGERS (which must
stay bitwise — the control that keeps a set-specific fix from breaking the
numeric case), the plain `a = a | b` spelling, and a file mixing `|=` with list
and int `+=` accumulators.
