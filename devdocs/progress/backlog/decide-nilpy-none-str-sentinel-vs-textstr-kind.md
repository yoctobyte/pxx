---
track: U
prio: 40
type: decide
blocked-by: []
summary: "Re-ask of decide-nilpy-none-str-representation: the chosen fix (a NilPy string kind whose blocks may be zero length) rests on a block kind that nothing in the tree ever stamps, so it is a Track A representation project rather than a bugfix. A None SENTINEL closes the reported bug at a fraction of the cost — but closes less."
---

# `""` vs `None` for a NilPy str: keep the decided kind, or use a None sentinel?

Blocks [[bug-nilpy-empty-str-and-none-are-the-same-value]] (N, p40), which is
otherwise ready and re-measured green-to-start at 66d65dbbb.

## Why this is being re-asked

You settled this on 2026-08-11: **a NilPy string kind whose blocks may be zero
length.** Zero-length NilPy strings stop collapsing to nil; Pascal's
`AnsiString` keeps collapsing; nil goes back to meaning only None.

That decision assumed the block-kind machinery was in place. It is not, and that
was not visible on 2026-08-11:

- `PXX_KIND_TEXTSTR = 2` is declared (builtinheap.pas:174) and **never written**.
- `PXXStrMeta` (builtinheap.pas:382) stamps `PXX_KIND_LEGACY` on every string
  from both constructors, unconditionally.
- [[feature-nilpy-text-string-kind]] is genuinely done — NilPy `str` counts
  characters — but it got there via three frontend-typed helpers, so the
  header half of phase 2 was never needed and never built.

So there is no runtime predicate that answers "is this block a NilPy str?",
which is exactly what the decided fix must ask before deciding to collapse.

## Option A — build the decided design (stamp TEXTSTR for real)

1. A kind-carrying string constructor; NilPy user code emits literals through it
   (`NilPyUserCode`, symtab.inc:25, is the hook that already exists).
2. Propagate the kind through **every string-producing routine** — concat,
   slice, join, format, case mapping, the pylib str surface — because the bug is
   reported for `"" + ""` and `"ab"[0:0]`, not only for literals. Anything less
   leaves half the producers wrong.
3. A non-nil zero-length handle then circulates in a runtime with **208 `= nil`
   tests in `compiler/builtin/**`**, some of which mean "empty". Each must be
   read; this is where the self-host gate can break.

- **Closes:** `"" is None`, and `s == ""` on a None-str (CPython: False), and
  every future question of the same family.
- **Costs:** a Track A representation project, multi-session, with real
  self-host exposure. The two other tickets circling this model
  ([[bug-nilpy-non-ascii-string-surface-measured]],
  [[bug-nilpy-encode-ignores-the-codec]]) would benefit from the same
  machinery, so the cost is shared rather than spent once.

## Option B — a None sentinel (cheap, closes less)

Invert it: `""` keeps collapsing to nil, and **None** gets the distinguished
representation — one canonical zero-length block, allocated once with a
saturated refcount so release can never free it. `pystr_none` returns it;
`pystr_is_none` compares against it.

- **Closes:** `"" is None` — the reported bug — with no producer changing at
  all, because nil simply stops meaning None.
- **Leaves open:** `s == ""` on a None-str still answers True where CPython says
  False (it answers True today as well, so nothing regresses).
- **Costs:** `pystr_none` / `pystr_is_none` plus the frontend sites that
  materialise None into a str slot. Pascal `AnsiString` untouched by
  construction, same as option A. A global singleton is the smell, and a
  sentinel that ever gets freed or copied is a silent wrong answer rather than
  a crash — so it wants a test that a None-str survives a round trip through
  concat, a list, and a variant.

## Option C — park the bug and take it as part of the string-model project

Do neither now; let [[bug-nilpy-empty-str-and-none-are-the-same-value]] wait for
whenever the kind stamping is built for another reason. Honest, and costs
nothing — the bug is a wrong answer only for programs that write `is None` on a
str, which is a Python idiom but not a common one.

## Recommendation

**B now, A later** — and deliberately, not as a permanent answer. B turns a
silently wrong answer into a right one this week for the cost of two routines,
and it does not foreclose A: when the kind stamping is built for the *other*
reasons (encoding, the non-ASCII surface), the sentinel is deleted and nil
becomes free again. The argument against B is that a half-closed semantics can
be worse than an open one — `is None` right and `== ""` wrong is a stranger
world than both wrong — and that is the part worth your judgement rather than
mine.

---

## MEASURED 2026-08-16 — there is an Option D, and A/B are both aimed at the wrong layer

Measured against `stable_linux_amd64/default/pinned`, CPython 3 as the oracle,
six probes over every shape that can hold a NilPy str. **The result is a clean
split along one axis, with no exceptions found:**

| the slot's static type (`PXXDBG=n.locals`) | behaviour |
| --- | --- |
| **tk=22 (Variant)** | matches CPython on **every** row |
| **tk=23 (AnsiString)** | `""` is reported `is None` on every row |

Shapes measured. Variant, all correct: an unannotated parameter; a def that can
return None without an annotation (`maybe()`); a dict value; a list element; a
local assigned `""` then `None`. AnsiString, all wrong: a local `e = ""`; a
`s: str` annotated parameter; a class field `self.name = ""`; an empty slice
`"abc"[3:]`; an unentered `for` loop's variable.

### Why the split falls exactly there

`pyparser.inc:2549-2580` lowers `x is None` **on the static type**. The Variant
arm does a tag test (`PyMakeTagTest`, VT_EMPTY) — that is right by construction.
The string arm calls `pystr_is_none`, which is

```pascal
Result := Pointer(s) = nil;    { pylib.pas:12066 }
```

and an empty `AnsiString` *is* a nil handle. So the reported bug is not a heap
representation problem at all: it is one arm of a three-way lowering testing a
property that does not mean what it is being asked.

### The real finding: TWO mechanisms serve this one concept

Both are already in `pyparser.inc`, layered over time, and they disagree:

1. **Widen to Variant** — the newer one. Line 1201: *"Optional[str] is a VARIANT
   everywhere, parameters included"*, added by
   [[feature-nilpy-optional-string-param-accepts-none]] after the *opposite*
   collapse (str→variant at a call site) produced a wrong answer. The inference
   already widens wherever None can flow in — measured above.
2. **The nil-handle sentinel** — the older one. `pystr_none` / `pystr_is_none`,
   materialised at two sites (`return None` from a str-returning def,
   pyparser.inc:23622; `x = None` into a str-typed target, :23860).

`devdocs/dev/normalise-dont-special-case.md` names this exactly: a construct
reachable through two shapes, and the second path is the one that stays broken.

**And the sentinel is broken in BOTH directions**, which the ticket above did not
know. `-> str` def returning None (stays tk=23, so the sentinel is live):

| | pxx | CPython |
| --- | --- | --- |
| `b is None` | True | True |
| `b == ""` | **True** | **False** |

The same local written `c = ""; c = None` widens to tk=22 and gets **both**
right. So the "half-closed semantics — `is None` right and `== ""` wrong" that
the recommendation flagged as the argument against Option B **is what already
ships**, in the sentinel mechanism B proposes to keep and harden.

### Option D — finish the migration, delete the sentinel

Make mechanism 1 the only one: a str slot that can hold None is a Variant (the
inference does this already in every shape measured except the two sentinel
sites). Then

- `pystr_none` / `pystr_is_none` are deleted, and nil goes back to meaning only
  "empty AnsiString" — which is what Pascal has always meant by it;
- the string arm at pyparser.inc:2568 folds to **constant False**: a slot that
  is statically a `str` cannot be None once the widening is complete, so the
  call was always answering a question that should not have been asked;
- `s == ""` on a None-str comes out right too, because a Variant None already
  compares correctly (measured).

**Against Option A:** D closes strictly more (A leaves `== ""` to the same
comparison paths; D routes it through the tag that already handles it), and
costs no heap work at all — no kind stamping, no producer propagation, and it
never puts a non-nil zero-length handle into circulation, so the ~357 `= nil`
tests in `compiler/builtin/**` are not touched. `PXX_KIND_TEXTSTR` stays unused
and unblocked for whenever encoding work genuinely needs it.

**Against Option B:** B hardens the mechanism that is measurably the wrong one,
and inherits the `== ""` defect shown above rather than fixing it.

**The real work in D** is the two sentinel sites: a `-> str` annotated def that
returns None, and `x = None` into an already-str-typed target. Both must widen
the slot to Variant instead of storing a nil handle. The `-> str` case is
arguably a user type error (the annotation promises a str) — CPython does not
enforce annotations, so upward compatibility says accept it and widen. Scope it
before committing: this is a frontend inference change under Track N's gate,
not the multi-session Track A representation project A would have been.

### Bearing on the blocked bug

[[bug-nilpy-empty-str-and-none-are-the-same-value]] is **not** blocked on a
representation decision. Its repro rows (`""`, `"" + ""`, `"ab"[0:0]`,
`"".join([])`) are all tk=23 locals, and all four are the same single defect.
