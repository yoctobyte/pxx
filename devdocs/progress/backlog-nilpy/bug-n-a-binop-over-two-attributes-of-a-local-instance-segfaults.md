---
track: N
prio: 75
type: bug
blocked-by: []
summary: "`q = P(a, b); return q.x + q.y` inside a FUNCTION segfaults the produced binary — any binary operator whose BOTH operands are attribute reads of a class instance held in a function LOCAL. Works at module scope, works as `self.x + self.y` inside a method, works with one attribute (`q.x + 1`), works when the two reads are spilled to locals first (`t = q.x; u = q.y; t + u`). Reproduces on the PIN and on the tip, at every -O level, for int and str attributes, and with two different instances (`q.x + r.y`). Found incidentally 2026-09-02 while probing the AST cloners; not diagnosed."
status: backlog
owner: —
---

# A binop over two attribute reads of a local instance segfaults

## The repro

```python
class P:
    def __init__(self, a, b):
        self.x = a
        self.y = b

def total(a, b):
    q = P(a, b)
    return q.x + q.y      # SIGSEGV in the produced binary

print(total(1, 2))        # CPython: 3
```

No diagnostic: the compile is clean (`ok: ... procs=1930`) and the binary
faults at run time.

## The boundary, measured

Every row below is `stable_linux_amd64/default/pinned`, and the tip agrees.
The oracle is CPython on the same file.

| shape | result |
| --- | --- |
| `q.x + q.y` in a function, `q` a local instance | **SEGV** |
| `q.y + q.x` — operand order swapped | **SEGV** |
| `q.x * q.y` — a different operator | **SEGV** |
| `q.x + r.y` — two DIFFERENT local instances | **SEGV** |
| `q.x + q.y` where the attributes are `str` | **SEGV** |
| `q.x + 1` — only ONE attribute read | ok |
| `t = q.x; u = q.y; return t + u` | ok |
| `print(q.x); print(q.y)` — both read, not in one binop | ok |
| the same expression at MODULE scope | ok |
| `self.x + self.y` inside a method | ok |

So it is not attribute access, not the class, not the operator and not the
number of reads — it is **two attribute loads as the two operands of one binary
operator, when the instance lives in a function local.** `self` is exempt,
which is the tell worth starting from: a method's receiver is a parameter and
reaches the same binop through a different lowering than a local assigned from
a construction.

A NilPy construction is the `AN_CALL` with a NEGATIVE proc id whose record
identity lives in `ASTRight` (symtab.inc's `ResolveNodeRec` construction arm),
and `SymIsCtorResultTemp` marks the conduit local it is spilled through. Both
are specific to the local-assigned-from-construction path and neither applies
to `self`. That is where I would look first; I did not.

## Why the `+` variant answers `TypeError` instead

Wrapping the same expression in a loop —

```python
s = 0
for i in range(1, 5):
    s = s + total(i, i * 2)
```

— reports `Unhandled exception: TypeError: expected a number, got object`
rather than faulting. Same defect, different landing: the corrupted value
survives long enough to be type-tagged. A test asserting only "no crash" would
call that one a pass.

## Provenance

Found while sweeping the corpus for
[[bug-a-generic-astleft-astright-walkers-recurse-into-kinds-that-overload-those-fields]];
it is NOT that bug — it reproduces on the pin, at `-O0`, with no cloner
involved. Filed rather than fixed because it is a NilPy lowering question in
another lane and the diagnosis is worth more than a guess. The ten-row table
above is the whole of what is known.

## A reading of the table (frankA, 2026-09-02) — not verified, but it fits all ten rows

Every row varies one axis, and the pattern is **not** a defect in attribute
reads or in binary operators. It is a LIFETIME: the first operand's evaluation
releases or invalidates something the second still needs, and that only shows
when both live across the same operator. Splitting into two statements gives
each read its own sequence point and its own local, which is exactly the row
that works. It looks like an operator bug and is a temp bug.

`self` being exempt is the confirming half rather than a separate fact: `self`
arrives as a PARAMETER and is not a construction-assigned local, so whatever
the constructor path does to its result temp never happens to it. The specific
question to ask first is **whether the ctor result temp is released at the end
of the ASSIGNMENT rather than at the end of the enclosing statement**.

The loop row is the most useful one in the table and looks like a curiosity:
the same corruption lands one step later as `TypeError: expected a number, got
object` instead of SIGSEGV. A defect whose symptom moves between a signal and a
type error under an irrelevant perturbation is one whose test must assert the
VALUE — a crash-only guard passes the loop form.
