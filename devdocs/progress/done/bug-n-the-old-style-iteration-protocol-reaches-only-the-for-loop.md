---
track: N
prio: 72
type: bug
blocked-by: []
summary: "A class with __getitem__/__len__ now iterates with `for`, but every OTHER consumer of iteration still refuses it — and `list(b)` returns [] SILENTLY. Found while fixing feature-nilpy-for-loop-getitem-protocol-fallback; the for-loop was one path of several serving one concept."
status: done
owner: agent-A
---

# The old-style iteration protocol reaches only the `for` loop

Filed 2026-08-19 from [[feature-nilpy-for-loop-getitem-protocol-fallback]], which
fixed the `for` lowering. The repo's own rule says to grep for the sibling arms
before closing a double case, so this is those siblings.

All rows measured at HEAD **and on pinned** — every one is pre-existing, none is
a regression from the for-loop fix.

```python
class Box:
    def __init__(self, items): self.items = items
    def __getitem__(self, idx): return self.items[idx]
    def __len__(self): return len(self.items)
b = Box([1, 2, 3])
```

| shape | CPython | pxx |
| --- | --- | --- |
| `for x in b` | 1 2 3 | **fixed** — 1 2 3 |
| `[x*2 for x in b]` | `[2, 4, 6]` | **fixed** — shares the lowering |
| `list(b)` | `[1, 2, 3]` | **`[]` — SILENT WRONG VALUE** |
| `sum(b)` | `6` | `TypeError: expected a str, a list or a dict, got object` |
| `2 in b` | `True` | `TypeError: argument is not a container (no __contains__)` |
| `p, q, r = b` | `1 2 3` | compile error |

## The one that matters most

**`list(b)` answers `[]`.** Not an error — an empty list, which flows onward and
produces a wrong result far from its cause. That is this repo's expensive
failure shape, and it is the reason this is filed as a `bug` rather than a
feature request. The other rows fail loudly and are merely missing.

## Shape of the fix

One concept — "this object is iterable by index" — is served by several
independent paths: the `for` lowering (now fixed), `list()`/`sum()`'s container
conversion, the `in` operator's `__contains__` check, and tuple unpacking. Each
tests for a container in its own way, which is why fixing one moved none of the
others.

The right fix is almost certainly NOT four more special cases but one shared
"materialise this receiver as a sequence" helper the four consumers call —
`normalise-dont-special-case`. `pyiter_of_userobj` already exists for the
`__iter__` protocol and is the natural place for the `__getitem__` fallback to
live, so that every consumer that already goes through a cursor gets it at once.

## Also still missing: `__getitem__` WITHOUT `__len__`

CPython walks 0.. and stops on `IndexError`, so a class with only
`__getitem__` is iterable. pxx requires both and now says so explicitly rather
than dying with "pylib (count) not loaded". Loud and honest, but still a gap.

## Root cause (2026-08-27) — the divergence is in pylib, not in the frontend

Every consumer in the table selects the **variant** overload of its builtin
(`list(const v: Variant)`, `sum(const v: Variant)` …), measured by printing the
resolved proc at the call site — so `PyNodeIsUserIterable` and the frontend's
argument-normalising machinery never decide any of these. The runtime chain does,
and it had `PyUserObjHasDunder(o, '__iter__')` at each of its gates. A
`__getitem__` class failed that test, fell to each gate's default, and `list()`'s
default is an EMPTY LIST — which is why the row that mattered was silent.

The frontend was not innocent, but only in one place: the `for` lowering refused
`__getitem__` WITHOUT `__len__` at compile time, because its index loop snapshots
a length before the walk and cannot express "stop on IndexError".

## Fix — one predicate per side, plus the cursor that was missing

**Runtime (`compiler/builtin/pylib.pas`).**
- `PYITER_SEQOBJ`, a cursor that walks `obj[0]`, `obj[1]`, … stopping on
  `__len__` when the class has one and on the IndexError `__getitem__` raises
  when it does not. Both terminators, because a class may have either.
- `pyiter_of_userobj` builds it when there is no `__next__` but there is a
  `__getitem__`, instead of raising. That is what makes every consumer agree:
  they already route through this one constructor.
- `PyUserObjIterable(o)` — `__iter__` OR `__getitem__` — replacing the
  `__iter__`-only test at both gates (`pyiter_v`, `pyseq_of_obj`).
- A `__getitem__` the arity-2 dispatcher cannot call RAISES rather than ending
  the walk. Answering "exhausted" there would put back the exact silent empty
  result this ticket is about.

**Frontend (`compiler/pyparser.inc`).**
- `PyUClassIsIterable(ci)`, the one predicate for "iterable by either protocol",
  behind the three sites that each tested `__iter__` alone
  (`PyIterArgAsList`, `PyMakeIterOf`, `PyNodeIsUserIterable`).
- The `for` lowering routes a `__getitem__`-WITHOUT-`__len__` class to the
  cursor. The index loop stays the path for `__getitem__` + `__len__` — it is
  correct, gate-tested, and is what pylib's own containers use — so this adds a
  case to the *decision*, not a second implementation of the walk. The refusal
  it replaces is now narrowed to a class with neither protocol.

## Also fixed, found by the witness test

`reversed()` over ANY user object answered `[]` — the `__iter__` protocol
included, so this was never about `__getitem__`. `reversed(const v: Variant)`
had its own chain that fell to an empty cursor. It now materialises through
`pyseq_of_obj` like every other consumer. Note `reversed()` over an
`__iter__`-only class is a TypeError in CPython and answers `[3, 2, 1]` here;
that is the laxness the routine's own comment already declares for a cursor
operand, and CLAUDE.md's "we accept a form CPython rejects" row.

## Verified against the CPython oracle

`test/test_nilpy_getitem_iteration_protocol.npy` (+ `.expected` generated by
CPython), registered in `test-core`: `for`, comprehension, `list`, `tuple`,
`sum`, `max`/`min`, `in`, `sorted`, `reversed`, `zip`, `enumerate`, `map`,
`any`/`all`, tuple unpack and `join` — every one of them over a `__getitem__`
class, plus the `__getitem__`-without-`__len__` shape and the modern `__iter__`
protocol as the non-regression arm. GREEN at HEAD; at `pinned` the program did
not even compile.

`make compiler/pascal26` fixedpoint + `tools/gate.sh quick` GREEN, then
`make stabilize-fast && make pin` (v378) — the pin is required because this
changes `compiler/builtin/**`, which other lanes build from the frozen copy.

## Log
- 2026-08-27 — resolved, commit 9dd5c7ef4.
