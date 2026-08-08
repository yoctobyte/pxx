---
track: N
prio: 45
type: bug
summary: "SILENT->CRASH: a local assigned instances of two unrelated classes keeps ONE static class identity, so every member access uses that layout. `o = DC(...)` then `o = PC(...)` reads o.native at DC's offset for both — a segfault when the layouts differ."
---

# A local reassigned across two classes keeps one static class

```python
@dataclass
class DC:
    name: str
    native: Optional[Callable[[int], None]] = None

class PC:
    def __init__(self, name, native=None):
        self.name = name
        self.native = native

o = DC("a", plain)
o.native(1)          # SIGSEGV — before printing anything
o = PC("b", plain)
o.native(2)
```

CPython prints `plain 1` / `plain 2`.

## Measured, not inferred

`PXXDBG=n.locals` reports `<module> o tk=6 rec=1` — tk 6 is tyClass, so `o` is
a single STATIC class, NOT a variant. Both member accesses compile against that
one class's layout, and the access on the instance of the OTHER class reads the
field at the wrong offset and jumps through whatever is there.

A `PXXDBG` probe on the variant-field-call candidate scan confirms the other
half: `PyMakeVariantFieldCall` is never reached for this program. It is not the
dynamic-receiver path at all.

The layouts must DIFFER for it to bite — with `native` at the same offset in
both classes the wrong cast is harmless, which is why this hid behind
[[bug-nilpy-dynamic-receiver-callable-field-casts-to-the-wrong-class]] (whose
own repro was this shape by mistake; corrected there).

## Where it comes from

`PyCollectLocals` deliberately takes "the latest resolved class whenever it
differs" — added so that `with open(...) as f` followed by a later
`f = open(...)` would not keep the first round's class forever. That rule is
right for a name whose class is *refined*; it is wrong for one that genuinely
holds two unrelated classes, where the answer is that the local has NO single
static class and should be a VARIANT.

## Shape of the fix

Widen to a variant when two assignments resolve to unrelated classes (neither a
subclass of the other) — the same "no single answer, use the dynamic path"
conclusion the method/field scans reach. Note the cost: it moves such a local
onto the runtime-dispatch path, which is slower but correct, and it is the
representation CPython semantics actually require.

Check the sibling first: `PyWidenBinding` already exists for the type-kind half
of this question, so this may be one arm added there rather than a new rule.

## Gate

The program above matching CPython, plus a control that a local refined to a
SUBCLASS still keeps its static class (that is what the "latest resolved class"
rule exists for), plus the per-fix loop.
