---
track: N
prio: 80
type: bug
blocked-by: []
summary: "`def f(): h = Holder(); return h.c.v` declared the INTERMEDIATE hop's class as its result type and segfaulted the caller. FIXED 2026-09-15; the `return mk().v` shape (a field off a CALL result) is the named residual."
---

# A def returning a multi-hop attribute chain is typed by the hop before last

**FIXED 2026-09-15.** Kept open only for the residual named at the foot.

```python
class Cell:
    def __init__(self, v):  self.v = v
class Holder:
    def __init__(self):     self.c = Cell(20)

def f():
    h = Holder()
    return h.c.v

print(f())        # CPython 20      pxx SEGV, no diagnostic
```

Reproduced on the pinned compiler (v410) and on HEAD before the fix, so it was
live in every `$(PXX_STABLE)` consumer, not a recent regression.

## Mechanism

`PyInferDefRetTypeScanInner` types a def whose whole body ends in a `return`.
It had an arm for `return q.n` gated on an **equality** — `e = j + 4`, exactly
one hop — and an arm for `return q.m(...)`. Two hops matched neither and fell
through to the expression chase, **which types the RECEIVER**. So `f` declared
a `tyClass` result (Cell, the intermediate) while returning an int, `$pyresult`
got a class-typed slot, and `print(f())` read a small integer as an object
pointer.

The IR shows it directly. Broken, `PXXDBG=a.ir:f`:

    18: load_sym [sym=h]  tk=6
    19: field ival=8 tk=6           <- h.c
    20: load_mem tk=6
    21: field ival=8 tk=22          <- .v, ADDRESS ONLY
    22: arg tk=22
    ...
    28: store_sym [sym=$pyresult] tk=6     <- tyClass, from a variant value

Fixed, the same chain ends `load_mem` -> `var_store` into a `tk=22` `$pyresult`
that is `zero_sym`'d at entry.

**This is the same rule implemented a third time, one shape at a time.** The
one-hop arm's own header already warns about the chase typing the receiver; the
method arm's header says *"Same defect, one token further along"*. Nobody asked
what the SET was.

## Why it survived

**Every spelling anyone would reach for to check it was already green**,
measured on the unfixed compiler:

| spelling | unfixed |
| --- | --- |
| `h: Holder = Holder(); return h.c.v` | OK — the annotation retypes it |
| `x = h.c; return x.v` | OK |
| `r = h.c.v; return r` | OK |
| `return h.c.v + 0` | OK |
| `print(h.c.v); return h.c.v` | **OK — the earlier read rescues it** |
| `return self.c.v` in a method | OK |
| `return xs[0].v`, `return d["k"].v` | OK |
| module scope | OK — no `$pyresult` |
| `def f() -> int: ... return h.c.v` | OK |

The `print then return` row is the sharpest: **adding a diagnostic print makes
it work**, which is the worst property something being debugged can have.

**AND THE LEAF'S TYPE DECIDES WHETHER IT IS VISIBLE AT ALL.** With a CLASS leaf
the wrong answer (the intermediate's `tyClass`) and the right one COINCIDE and
nothing goes wrong. Only a non-class leaf separates them — `int`, `str`, `float`
and `list` leaves all crashed. This is the collision rule in CLAUDE.md ("if the
machinery did nothing at all, would this row still pass?") with the default
being *another correct-looking class*.

## The fix

`PyRetFieldChainType` walks the chain hop by hop from the receiver's class,
answering the LAST hop's type; the arm is gated on `e >= j + 6` with a `tkDot`
at `j + 4`. A hop through a non-class stops the walk and answers `tyUnknown`,
and — following the method arm's own reasoning verbatim — the caller then uses
`tyVariant` rather than falling through, because the chase would claim a class.

## RESIDUAL — `return mk().v`, a field off a CALL RESULT

```python
def mk():  return Cell(20)
def f():   return mk().v      # still SEGV
```

Same rule, a fourth shape: `ident ( ) . ident` rather than `ident . ident .
ident`, so the chain arm does not match it.

**Measured boundary, so the next reader does not have to find it again** — and
it is much narrower than "a call result":

| spelling | after the chain fix |
| --- | --- |
| `def mk()` at MODULE level, `return mk().v` | **SEGV** |
| the same with `def mk() -> Cell:` | **SEGV** — the annotation does not help |
| `def mk()` NESTED inside `f`, `return mk().v` | OK |
| `t = mk(); return t.v` | OK |
| `return Cell(20).v` (a CONSTRUCTOR, not a def) | OK |
| `return mk().v + 0` | OK |

So it is one cell: a **module-level** def's call result, field-read, as the
whole return expression. The nested case already works, which localises the
gap precisely — `PyNestedDefRetType` is the resolver and the existing bare-call
arm scans only `bodyScanStart .. j`, i.e. the ENCLOSING BODY, so a def at module
scope is outside its range. That arm is also gated on
`(cur = tyUnknown) or PyRetIsIntDefault(cur)`, and here the chase has already
answered a class, so it would not fire even with the range widened.

Not folded into the chain fix because widening a scan range and relaxing a
`cur` gate are two behaviour changes to a heavily-used inference path, and both
want their own tier run. There is also a recursion question — `PyNestedDefRetType`
calls `PyInferDefRetType`, and mutually-recursive defs (`a` returns `b().x`,
`b` returns `a().y`) have no guard today.

Stated rather than discovered later. It is the reason this ticket stays open.

## Gate

`make compiler/pascal26` converged (92ca0ab1b8e4); `tools/gate.sh quick` GREEN;
`make test-nilpy` green. `test/test_nilpy_a_def_returning_a_multi_hop_attribute_chain_is_typed_by_its_last_hop.npy`
is byte-identical to CPython and wired into the tier. Its positive control is
the PINNED compiler, on which it segfaults outright — which also means the
control cannot grade the individual rows, so the per-shape table above was
measured one program at a time instead.
