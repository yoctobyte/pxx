---
summary: "NilPy survey: repr(), __iter__/__next__, __getattr__, __delitem__ and a custom __hash__ are unsupported — all fail LOUDLY (compile error or raise), measured vs CPython"
type: bug
track: N
prio: 35
status: done
---

# Unsupported protocols: `repr()`, `__iter__`/`__next__`, `__getattr__`, `__delitem__`, `__hash__`

- **Type:** bug (NilPy, missing protocol support) — **Track N**
- **Opened:** 2026-08-01, from the CPython differential sweep (1094 cases,
  self-hosted binary at `3f2c5b915`).

A **survey ticket**, deliberately: these were found in one pass and share a
cause (the protocol is simply not implemented), but they are separate features.
Split into per-protocol tickets when picked up — do not treat this as one job.

## Why the low priority despite being real

Every one fails **loudly** — a compile error or a raise, never a wrong value.
That puts them well below the silent-wrong findings from the same sweep
([[bug-nilpy-bool-protocol-ignored-object-always-truthy]],
[[bug-nilpy-unary-numeric-dunders-return-raw-handle]],
[[bug-nilpy-ne-dunder-ignored-always-negates-eq]]) and below the one that
crashes ([[bug-nilpy-bitwise-shift-on-class-operand-segfaults]]).

## Measured

| case | CPython | pxx |
| --- | --- | --- |
| `repr(c)` | `REPR` | *compile error*: `undefined variable (repr)` |
| `for x in Countdown(3)` (`__iter__`/`__next__`) | `2 1 0` | *compile error*: `pylib (count) not loaded` |
| `C().missing_thing` with `__getattr__` | `GETATTR-missing_thing` | *compile error*: `"missing_thing": no such member on this record/class` |
| `del c[3]` with `__delitem__` | `DELITEM 3` | *compile error*: `del is supported on a dict subscript or a list slice` |
| `d[C(1)]` with `__hash__`+`__eq__` | `one` | `KeyError: key not found` |

### Notes per item

- **`repr()` is not a builtin at all.** `__repr__` *is* known to the compiler
  (it is used when printing), but the `repr(x)` function does not exist. Likely
  the smallest of these and the most commonly written.
- **`__iter__`/`__next__`**: `for x in <user object>` assumes a pylib container
  and looks for `count`. A custom iterator class is a normal Python idiom;
  supporting it means teaching the for-loop lowering the iterator protocol
  (including `StopIteration`), not just adding a name.
- **`__getattr__`**: attribute lookup is resolved statically against the class
  layout, so a dynamic fallback needs a runtime path — the largest of the five
  and the one most entangled with how NilPy types attributes today.
- **`__delitem__`**: `del` already handles dict-subscript and list-slice; this
  is the user-class arm of an existing construct.
- **`__hash__`**: a user object as a dict KEY. Related to, but distinct from,
  [[bug-nilpy-dunders-not-dispatched-through-containers]] — that one is about
  dunders on an instance *inside* a container; this is the instance being used
  as the container's key, needing `__hash__`/`__eq__` at runtime. Whatever
  [[decide-nilpy-runtime-dunder-dispatch-mechanism]] decides will likely settle
  this one too, so check that ticket before starting.

## Gate (per split-out ticket)

`make test-nilpy` + self-host byte-identical, plus a `.npy` diffed against
CPython's own output for the protocol in question, and a case where the class
does NOT implement it (must raise a catchable error, not compute garbage).

## 2026-08-09 — all five rows RE-MEASURED at HEAD; two are gone

The 2026-08-01 table is a snapshot and two of its rows have moved since — one
of them in the WRONG direction, which is the reason to re-measure rather than
work from it.

| case | 2026-08-01 | 2026-08-09 (measured) | status |
| --- | --- | --- | --- |
| `repr(c)` | compile error | **`''` — silent!** | **FIXED here** |
| `for x in Countdown(3)` | compile error `pylib (count) not loaded` | same | open → split out |
| `C().missing_thing` (`__getattr__`) | compile error | same | open → split out |
| `del c[3]` (`__delitem__`) | compile error | same | open → split out |
| `d[C(1)]` (`__hash__`) | `KeyError` | **works** | fixed 2026-08-08 |

### `repr()` — was reclassified by the re-measure

The ticket recorded it as a loud compile error, which is what put this whole
survey below the silent-wrong findings. It is not loud any more: `repr` gained
per-type overloads at some point, none of them for a user class, so a class
handle matched `repr(const s: AnsiString)` and was read as a managed string —
answering the EMPTY string. **A loud failure had quietly become a silent one.**

Fixed by adding the missing `repr(o: TObject)` overload, which forwards to
`pyvar_repr` — the same renderer a boxed element already used, so `repr(c)` and
`repr([c])` cannot disagree, and a class with no `__repr__` gets CPython's
`<__main__.C object at 0x..>` shape for free rather than a second default. An
overload, not a frontend intrinsic, per the note the file already carried above
`repr`: the ordinary resolution machinery does the dispatch and TPyList/TPyDict
keep their exact-match overloads.

Two hazards hit on the way, both now pinned by the test:

1. **Forward use.** The first version called a helper defined ~900 lines below
   with no entry in pylib's top declaration block. That does not fail to
   compile — it links to a plausible wrong address
   ([[project_bodyless_procaddr_links_to_entry_minus_one]]). `repr(c)` worked
   and `repr([c])` segfaulted.
2. **A borrowed box is a net RELEASE.** Boxing the object into a local variant
   without retaining looked safe ("it only lives for the call"), but the local's
   scope exit runs `PXXVarClear`, which releases an object-tagged slot. So
   `repr(c)` freed the caller's `c` and the next line read freed memory. Each
   line alone was fine; the SEQUENCE is the bug, and the test asserts the
   sequence. The same latent mistake was in the `__eq__`/`__gt__` reflected path
   added the same night and is fixed with it.

Verified: `test/test_nilpy_repr_of_user_object.{npy,expected}` (`.expected` from
CPython) — direct vs boxed vs nested, the same-variable sequence, `__str__`-only
vs `__repr__`, the no-dunder default shape, and scalar/container controls.
200k-iteration repr+`__eq__` loop holds RSS flat at 28MB, so neither the retain
nor the dunder dispatch leaks. `gate.sh quick` GREEN.

### `__hash__` — fixed 2026-08-08, not here

`d[C(1)]` works: [[bug-nilpy-container-membership-ignores-the-eq-dunder]] had to
teach `PyVarHashKey` about `__hash__` to keep "equal keys hash equal" once
`PyVarEq` started consulting `__eq__`. The row's own note predicted this
("whatever [[decide-nilpy-runtime-dunder-dispatch-mechanism]] decides will
likely settle this one too") and it is what happened.

### The three that remain

Split out as the ticket asked, rather than left in a survey that now reads as
half-done: [[bug-nilpy-iterator-protocol-on-a-user-class]],
[[bug-nilpy-getattr-dunder-not-supported]],
[[bug-nilpy-delitem-dunder-not-supported]]. This ticket is resolved as the
survey it was.

## Log
- 2026-08-09 — resolved, commit PENDING-COMMIT.
