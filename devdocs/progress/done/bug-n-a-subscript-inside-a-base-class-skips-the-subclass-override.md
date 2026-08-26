---
track: N
prio: 78
type: bug
blocked-by: []
summary: "`self[k]` written inside a base-class method binds to that class's own __getitem__ instead of the subclass override, so a mixin written the natural way raises the base's KeyError. Sibling arm of the already-fixed bug-n-a-builtin-subclass-subscript-operator-skips-the-override."
status: done
owner: agent-N-dispatch
---

# A subscript inside a base class skips the subclass override

Filed 2026-08-19 from [[feature-b-mimic-collections-abc-mapping-and-mutablemapping]].

Measured on **pinned v356** (`2bb09afb0cff`):

```python
class Base:
    def __getitem__(self, k):
        raise KeyError(k)
    def fetch(self, k):
        return self[k]          # <-- binds to Base.__getitem__
class Sub(Base):
    def __getitem__(self, k):
        return 'val-' + k
print(Sub().fetch('x'))
```

| | |
| --- | --- |
| CPython | `val-x` |
| pxx (pinned v356) | `Unhandled exception: KeyError: 'x'` |

`self.__getitem__(k)` spelled explicitly **does** dispatch correctly — only the
`[]` operator form is statically bound. That asymmetry is the bug: two mechanisms
serve one concept and only one of them is virtual.

Sibling arm of
[[bug-n-a-mixin-cannot-iterate-self-and-an-abstract-iter-breaks-its-overrides]]
(same defect via `for x in self`) and of the already-resolved
`bug-n-a-builtin-subclass-subscript-operator-skips-the-override`, which fixed the
builtin-base arm of the same double case without the user-base arm. Third sighting
of one root cause — `devdocs/dev/root-cause-over-microfix.md` says that is a design
flaw, not three bugs.

Track B workaround: `lib/rtl/mimic_collections_abc.py` spells every internal
subscript `self.__getitem__(k)`. Registered in
`devdocs/dev/track-b-workarounds.md`.

## Resolution (2026-08-26)

**The ticket's title was right and its repro was measuring something else.**
Both had to be fixed; they are separate root causes and this ticket needed both.

### What the dispatch was actually consulting

`PyCallMeth1/2/3` — the single funnel for *every* dunder in this frontend
(`__getitem__`, `__setitem__`, `__len__`, `__contains__`, `__str__`, `__bool__`,
`__eq__`, `__lt__`, `__add__`, `__enter__`, `__exit__`, `__index__`, …) —
allocated a bare `AN_CALL` with `ASTIVal := UMthProc_[FindUMeth(ci, mname)]`.
That binds the method found on the receiver's **declared** class. Nothing about
`self` was special: the receiver's static type was the whole story, and from
outside a class it merely *happened* to be exact.

The ordinary method-call path (`PyParseMethodCallArgs`, ~5000 lines below) has
tested `UMthVirSlot[mmi]` and allocated an `AN_VIRTUAL_CALL` since virtual slots
landed. **14 sites in `pyparser.inc` already made that test; the three
`PyCallMethN` helpers did not.** That is the whole bug.

`self.__getitem__(k)` "dispatching correctly" (the ticket's asymmetry) is the
same fact seen from the working side — it goes through the method-call path.

### The boundary, measured

| shape, asked from inside a base method | before | after |
| --- | --- | --- |
| `len(self)` | base's | override's |
| `k in self` | base's | override's |
| `str(self)` | base's | override's |
| `self[k]` | base's | override's |
| `self[k] = v` | base's | override's |
| `for x in self` | **override's already** | unchanged |

`for x in self` was the arm that was already right — the for-header desugarer
builds its own `AN_VIRTUAL_CALL` — and it is what named the specification. It
also means [[bug-n-a-mixin-cannot-iterate-self-and-an-abstract-iter-breaks-its-overrides]]'s
first half was a **misdiagnosis**: iterating `self` was never statically bound.

### The fix

One helper, `PyAllocMethCallNode`, delegated to by all three `PyCallMethN`
(`devdocs/dev/normalise-dont-special-case.md` — no third path). It copies the
method-call path's test verbatim, including its `PyClassInHierarchy` guard.

**Plus an exclusion that guard did not cover:** pylib's own classes. `class
D(dict)` puts `TPyDict` in a hierarchy, and `TPyList.at` / `TPyDict.fetch` /
`store` / `count` are reached through `PyCallMeth1` too — so without
`PyRecIsPylibOwnClass`, every container read in such a program silently changed
node kind. Caught by `test_nilpy_builtin_subclass_dunder_dispatch` going red,
not by inspection.

**And one consumer had to learn the sibling node kind:** the `del c[k]`
lowering reads the subscript back off the node the grammar built and tested it
for `AN_CALL`, so a user class with a parent fell to the refusal that lists the
very form being used. `AN_VIRTUAL_CALL` accepted there too.

### The second cause, which the repro was actually hitting

The repro's `Base.__getitem__` body is `raise KeyError(k)` — an **abstract
method**. `PyInferDefRetTypeScan`'s floor is `tyInteger`, so it registered a
method *returning an integer*; `PyRegisterClassMembers`' override block then
imposes the base's signature on every override (they share a VMT slot and must
agree). So the subclass's `str` result came back as a **pointer**, and its `str`
argument as `expected a number, got str` — which is the error the repro shows,
and it reproduces **from outside the class, with no `self` anywhere**.

Written up in full in the sibling ticket, whose title names it. Fixed by typing
a raise-only body `tyVariant` in `PyInferDefRetType`, which both the frame and
signature consumers reach.

### Verification

- verbatim ticket repro: `KeyError: 'x'` (pinned v376 and HEAD before) → `val-x`
- `test/test_nilpy_dunder_on_self_reaches_the_override.npy`, wired into
  `test-core`, `.expected` generated by CPython. Six rows wrong at pinned v376
  and the program then dies at section 2. Every row is a **pair** — external
  receiver beside `self` — so a reintroduced bug reads as the two arms
  disagreeing.
- `make compiler/pascal26` fixedpoint green; the dunder, class, iterator,
  `with` and mimic-library tests re-run individually and green.

### Filed rather than fixed

`NodeEnumIdOf`'s `AN_CALL` arm (`pasparser_expr.inc:9023`) and `PyEvalOnce`'s
chained-receiver test (`pyparser.inc:35419`) both pattern-match `AN_CALL`
without the `AN_VIRTUAL_CALL` sibling. Both **pre-date this change** — the
method-call path has emitted virtual calls all along — so they are their own
finding, not part of this fix.

## Log
- 2026-08-26 — resolved, commit 18d98d765 (the fix), 4fb78cf2d (the write-up).
