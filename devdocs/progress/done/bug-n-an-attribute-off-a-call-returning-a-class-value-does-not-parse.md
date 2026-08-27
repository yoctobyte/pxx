---
track: N
prio: 58
type: bug
owner: frank1-AN
blocked-by: []
summary: "`P(7).mk().a` is `unexpected token` — not a wrong value, a PARSE error — when `mk` returns a class-reference construction (`cls(...)` / `self.__class__(...)`) AND the class has a subclass. Without the subclass the identical file compiles. The subclass is what makes the name resolve to a set, and the representative's return type is what the selector arm reads."
status: done
---

# An attribute off a call returning a class VALUE does not parse when a subclass exists

```python
class P:
    def __init__(self, a):
        self.a = a
    def mk(self):
        cls = P
        return cls(self.a)      # a classref VALUE call -> variant

class Q(P):                     # <-- delete these two lines and it compiles
    pass

print(P(7).mk().a)              # CPython: 7    pxx: pascal26:11: error: unexpected token
```

```
Expected: ), but got:  (Kind: 81, Line: 11)
pascal26:11: error: unexpected token
  near:    mk   >>>  a
```

## PRE-EXISTING

Measured identical on `stable_linux_amd64/default/pinned` (v384) and on the
fixedpoint carrying [[bug-n-self-class-cannot-be-called-as-a-constructor]],
2026-08-27. Filed from that ticket's sibling sweep, where `self.__class__(...)`
made the shape easy to reach — but it is not that ticket's doing, and the repro
above deliberately uses `cls = P` so it needs no `__class__` at all.

## The boundary, measured

Varying one thing at a time (the failing selector is `.a`, an ordinary field —
`__class__` behaves no differently, which is what rules the dunder out):

| method returns | subclass? | `P(7).mk().a` |
| --- | --- | --- |
| `P(self.a)` — a static ctor | yes | **ok** |
| `cls(self.a)` — a classref value | no | **ok** |
| `cls(self.a)` — a classref value | yes | **unexpected token** |
| `self.__class__(self.a)` | no | **ok** |
| `self.__class__(self.a)` | yes | **unexpected token** |

So it needs BOTH a variant-typed (classref-constructed) return AND a same-named
method set. Neither alone does it.

## Where to look

Not the classref lowering — that is fine in every row above; the value it
produces is correct and `x = P(7).mk()` then `x.a` on a separate line works.
It is the SELECTOR arm after a call: `.` + ident off a call result is claimed
either by the static-class arm (`tk = tyClass`) or by the variant-receiver arm
(pyparser.inc, the `(tk = tyVariant) and (CurTok.Kind = tkDot)` test around the
`bug-nilpy-attribute-off-a-subscript-of-a-call-result-yields-the-variant-tag`
comment). With a subclass present the call's `tk` is evidently neither, so
nothing claims the `.` and the expression simply ends.

`FindProc` returns the *representative* of a same-named set and its `RetType` is
what type inference reads — the hazard called out at length in
[[bug-nilpy-redefining-a-def-rebinds-calls-that-came-before-it]]. A subclass is
what turns `mk` into a set of two, so the representative's `RetType` is the
first suspect. **Measure it — `PXXDBG=n.procs` and `a.ast:`** — rather than
assuming; this is exactly the block whose own comments record having broken
self-host and `sum(range(i))` before, and a wrong root cause recorded here is
worth more than the bug.

## Why it matters

A parse error is the good failure mode — nothing silently wrong ships. But the
shape is ordinary: a factory method plus a subclass is the reason to write a
factory method at all, and the diagnostic (`unexpected token` at the field name)
names neither the class-value return nor the subclass, so it reads as a typo.

## Resolution — a call is TWO node kinds and two chain loops knew one

**Fix:** `AN_VIRTUAL_CALL` added beside `AN_CALL` in two loops in
`pasparser_expr.inc` — the bare-ATTRIBUTE-on-a-call-result loop, and the
`.method()`-on-a-call-result loop above it. Both are `PyExprMode`-guarded, so
Pascal is untouched; self-host verified.

A method on a class that participates in a hierarchy is dispatched through the
VMT and built as `AN_VIRTUAL_CALL`; everything else is `AN_CALL`
(`PyClassInHierarchy`, pyparser.inc ~15323). So a subclass anywhere in the file
changed the node KIND of a call in a class two lines above it, the loops did not
recognise it, nothing claimed the `.`, and the expression ended where it stood.

The subscript guard a few lines further down **already tested both kinds**. That
is what says these two loops had drifted rather than never known — the same
`normalise-dont-special-case` shape the file keeps meeting, with the sibling
sitting in the same routine.

### Three things this ticket asserted that measurement corrected

Worth recording because the ticket's "Where to look" would have sent the next
reader to the wrong file, and it argued for it convincingly.

1. **"`FindProc` returns the representative of a same-named set... the
   representative's `RetType` is the first suspect."** No. An unrelated class
   declaring its own `mk` does **not** trigger the bug; only a SUBCLASS of `P`
   does. It is inheritance, not name collision. And `PXXDBG=n.ret` reports
   `tk=22 rec=0` for `mk` with and without the subclass — the inferred return
   type is identical, and `ASTTk[callNode] := Ord(Procs[mpi].RetType)` is
   written the same way on both branches of the virtual/direct choice.

2. **"It is the SELECTOR arm... `PyParseClassRecordSelectors` (pyparser.inc)".**
   A probe at that routine's entry printed **nothing at all** for this program,
   in either the failing or the passing case. The NilPy chain for
   `P(7).mk().a` never enters it; the loops that handle it live in
   `pasparser_expr.inc` after the constructor intercept. A probe on the Pascal
   twin printed only RTL parses (`pyExpr=0`), which is how that was settled.

3. **`PyEvalOnce`'s `AN_CALL`-only test looked like the same bug and is not.**
   It sits at the top of `PyParseClassRecordSelectors` and has the identical
   shape; extending it changed nothing measurable — `b.add(2).add(3).n` answers
   `5` with a subclass present, on v388 and with the change alike — so it was
   **reverted rather than landed on plausibility**. The double-evaluation it
   guards does not reproduce through the virtual path today.

### Measurement note

An early boundary table in this session read "OK" for cases that in fact failed,
because the probe captured errors with `2>&1 >/dev/null` and pxx prints its
diagnostics on **stdout**: the errors were discarded and a leftover binary from
the previous row was run instead. Any pxx probe must test for the OUTPUT FILE's
existence, not for an empty stderr.

## Gate

Every shape, with and without the subclass, now agrees — which is the property
that was broken:

| expression | with `class Q(P)` | without |
| --- | --- | --- |
| `P(7).mk().a` | `7` | `7` |
| `P(7).mk().d["k"]` | `5` | `5` |
| `P(7).mk().mk().a` | `7` | `7` |
| `P(7).mk().txt().upper()` | `HI` | `HI` |
| `P(7).txt().upper()` (control, str result) | `HI` | `HI` |
| `R(4).make().v` (control, STATIC construction) | `8` | `8` |
| `o = P(7).mk(); o.a, o.d["k"]` (control, name receiver) | `7 5` | `7 5` |

All match CPython. The last two rows are the two shapes that were right all
along and are what made the asymmetry visible.

17 named chain / dispatch / dynattr canaries green
(`attr_off_subscript_of_call_result`, `chaining`, `deep_statement_chain`,
`class_name_chain`, `class_attr_shared_slot_via_call_result`, `dynattr`,
`dynattr_class`, `builtin_subclass_dunder_dispatch`,
`dunder_on_self_reaches_the_override`, `self_class_constructs`, …). Self-host
fixedpoint verified, `converged after 1 round(s)`.

**Test:** `test/test_nilpy_attribute_off_a_virtual_call_result.npy`
(+`.expected`, registered) — the seven rows above.

## Log
- 2026-08-27 — resolved, commit PENDING-COMMIT.
