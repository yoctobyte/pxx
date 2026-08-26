---
track: N
prio: 78
type: bug
blocked-by: []
summary: "A base class whose __iter__ only raises poisons every subclass override: `for k in self` inside a base method calls the BASE __iter__, and the subclass's real __iter__ is never reached — `iter() returned non-iterator of type 'Sub'`. This is the whole ABC mixin pattern."
status: done
owner: agent-N-dispatch
---

# A mixin cannot iterate `self`, and an abstract `__iter__` breaks its overrides

Filed 2026-08-19 from [[feature-b-mimic-collections-abc-mapping-and-mutablemapping]],
which is exactly this pattern: `Mapping` stores nothing and its entire value is
mixins that dispatch *down* into the subclass.

Measured on **pinned v356** (`2bb09afb0cff`):

```python
class Base:
    def __iter__(self):
        raise NotImplementedError('abstract')
    def keys(self):
        out = []
        for k in self:          # <-- binds to Base.__iter__, not Sub's
            out.append(k)
        return out
class Sub(Base):
    def __iter__(self):
        return iter(['a', 'b'])
print(Sub().keys())
```

| | |
| --- | --- |
| CPython | `['a', 'b']` |
| pxx (pinned v356) | `Unhandled exception: TypeError: iter() returned non-iterator of type 'Sub'` |

The error message is the tell: it reports `Sub` as the non-iterator, i.e. the
`for` lowering resolved `__iter__` **statically to the declaring class** and then
fell back to treating `self` itself as the iterator. The subclass override is
never consulted.

Sibling arm of [[bug-n-a-subscript-inside-a-base-class-skips-the-subclass-override]]
— same defect, different operator (`for x in self` vs `self[k]`). Per
`devdocs/dev/normalise-dont-special-case.md`, fix both arms together and grep for
a third (`len(self)`, `self.__contains__`, `repr(self)`).

Track B workaround in place (`lib/rtl/mimic_collections_abc.py`): every mixin
takes its keys via `self.keys()` rather than iterating `self`, and each abstract
method ends with a dead `return iter([])` after the `raise` so the return type is
inferrable. Registered in `devdocs/dev/track-b-workarounds.md`; revert when this
closes.

## Resolution (2026-08-26)

**This ticket's two halves have two different causes, and only the second one
is real. The first half is a misdiagnosis — and the error message the ticket
reads as "the tell" is pointing at something else entirely.**

### Half 1 — "`for k in self` binds to Base.\_\_iter\_\_" — DID NOT REPRODUCE

Measured directly, with a **concrete** base `__iter__`:

```python
class Base:
    def __iter__(self):  return iter(['base'])
    def keys(self):
        out = []
        for k in self: out.append(k)     # <-- the ticket's claim
        return out
class Sub(Base):
    def __iter__(self):  return iter(['a', 'b'])
print(Sub().keys())
```

Answers `['a', 'b']` at pinned v376 — **correct, before any fix**. The
for-header desugarer builds its own `AN_VIRTUAL_CALL`, so iterating `self` has
dispatched dynamically all along. It is the arm that was already right, and it
is what named the specification for the sibling ticket.

The ticket's reading of `iter() returned non-iterator of type 'Sub'` as "the
for lowering resolved `__iter__` statically to the declaring class" is exactly
the kind of plausible story `devdocs/dev/debugging-playbook.md` warns about. The
message comes from pylib's `pyiter_of_userobj`, and what it actually means is
"the value your `__iter__` handed back was not usable" — see half 3.

The genuinely static arm was `self[k]` / `len(self)` / `k in self` /
`str(self)`, which is the sibling ticket
[[bug-n-a-subscript-inside-a-base-class-skips-the-subclass-override]], now
fixed. Iterating `self` was never on that list.

### Half 2 — "an abstract \_\_iter\_\_ breaks its overrides" — REAL, and the whole story

This is the ticket's real content, and it is not about `__iter__`, or about
dunders, or about `self`. Reduced to six lines with an ordinary method:

```python
class A:
    def m(self, k):  raise KeyError('boom')     # abstract
class B(A):
    def m(self, k):  return 'b'
print(B().m('x'))          # CPython: b     pxx: 6459584   <- a POINTER
```

Add a dead `return ''` after the raise and it prints `b`. That is precisely the
workaround Track B's `mimic_collections_abc.py` carries, which is what made it
findable.

**Mechanism.** `PyInferDefRetTypeScan`'s floor is `tyInteger`, and a body that
only raises has no `return` to move it — so an abstract method registers as
*returning an integer*. That is a fiction: the body cannot return at all. It
stays harmless until the class is subclassed, because
`PyRegisterClassMembers`' override block then makes the override **adopt the
base's signature** (they share a VMT slot and must agree, which is the right
rule). The invented `tyInteger` is thereby imposed on every override — a `str`
result comes back as a pointer, a `str` argument as `expected a number, got
str`.

**Fix.** `PyInferDefRetType` types a body that raises and never returns a value
as `tyVariant` — the honest answer, and the one already used a few lines above
for the other "produces no value of its own" shape. Nothing is lost: the body
never reaches a return, so a variant Result is simply never written
(zero-init = VT_EMPTY = None), and an override of any type now marshals through
a slot wide enough to carry it. Both consumers — `PyParseDefHeader` (the frame)
and `PyMethodRetType` (the signature) — reach it through `PyInferDefRetType`, so
they stay in step by construction rather than by two copies agreeing.

### Half 3 — a third defect, found only because half 2 was fixed

With `__iter__` now variant-returning, the repro stopped raising and started
answering `[]`. Isolated with **no inheritance at all**:

```python
class Solo:
    def __iter__(self) -> Any:  return iter(['a', 'b'])
print(list(Solo()))     # CPython: ['a', 'b']    pxx: []
```

Green on pinned v376's *class*-returning spelling, red on the variant one, and
`-dPXX_HEAP_DEBUG` turns the same program into a **SEGV** — a use-after-free,
pre-existing and independent of both this ticket and its sibling.

`PyUserObjNoArgDunder`'s `RetKind = 22` (variant) arm took no reference, while
the `RetKind = 6` (class) arm three lines below does `PXXObjRetain`. Every
caller reads the payload back out with `pyvarobj` and keeps the raw pointer
after its own variant dies, so the class arm's retain is what had been keeping
the cursor alive. Two arms of one rule, only one updated — again. The object arm
is the specification; the variant arm now matches it.

**`compiler/builtin/pylib.pas`: this half does not reach Track B/E until a pin.**

### Track B workaround is now revertable

`lib/rtl/mimic_collections_abc.py` may drop both of its workarounds — the dead
`return iter([])` after each abstract raise (half 2) *and* taking keys via
`self.keys()` rather than iterating `self` (which half 1 shows was never
needed). Registered in `devdocs/dev/track-b-workarounds.md`; that revert is
Track B's call, not done here.

### Verification

- verbatim ticket repro: `TypeError: iter() returned non-iterator of type 'Sub'`
  (pinned v376 and HEAD before) → `['a', 'b']`
- the collections-ABC mixin pattern end to end — a `Mapping` that stores
  nothing, with `keys()`, `items()` and `get()` dispatching down into a `Bag`
  subclass — matches CPython, and is a section of the new test
- `test/test_nilpy_dunder_on_self_reaches_the_override.npy`, wired into
  `test-core`, `.expected` generated by CPython. Sections 2 and 3 are this
  ticket; at pinned v376 the program dies outright at section 2. Rows are
  **pairs** — concrete base beside abstract, class-returning `__iter__` beside
  variant-returning — so a regression reads as the two arms disagreeing.
- `make compiler/pascal26` fixedpoint green; `lib_mimic_collections_abc`, the
  iterator-protocol, `with`-protocol and dunder tests re-run individually and
  green.

## Log
- 2026-08-26 — resolved, commit PENDING-COMMIT.
