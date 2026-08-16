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

# CLOSED 2026-08-16 (user) — the decision stands; this re-ask should not have been filed

> "for nilpy we deliberately distinguish between nil (none) and an empty string.
> we even made a special string type (based on ansistring) for nilpy (similar to
> unicode strings etc). they all use same ansistring refcounting mechanism (with
> exception to not auto-nil an empty string on python). so, in pascal a nil
> pointer equals "", but not in nilpy." — user

That is [[decide-nilpy-none-str-representation]]'s DECIDED section, unchanged:
the third **kind**, `PXX_KIND_TEXTSTR`, gaining "may be zero length"; ordinary
AnsiString refcounting; the empty-collapse suppressed for NilPy-produced strings
only, so Pascal and the self-host binary are untouched by construction rather
than by audit.

**So option B is refused and option C is moot.** Option A was never a competing
design — it IS the decision, and this ticket mis-framed it as one candidate
among three.

## Why the re-ask happened, so it does not happen a fourth time

This ticket was opened because `PXX_KIND_TEXTSTR` is declared and never
stamped, and that was read as "the decided design rests on machinery that does
not exist, so re-open the choice." Wrong inference: unbuilt is not undecided.
The correct filing was an implementation ticket in Track N with the stamping as
its first step. Same failure as [[frank2-search-done-before-designing]] — a
negative measurement generalised into a design question.

I then re-measured the AnsiString-vs-Variant split from first principles and
proposed routing through variants, which is **option A of the original ticket**,
considered there and set aside on a stated ground this ticket did not carry:
the promotion boundary — not the representation — is where the variant route
goes wrong, and the kind has no promotion boundary at all. Read the decided
ticket before re-measuring, not after.

## The two findings from that measurement that DO survive

Both are corrections to the record, not reasons to reopen anything.

### 1. The sequencing note on the decided ticket is wrong — the kind is NOT stamped

It says *"`PXX_KIND_TEXTSTR` is stamped but not yet semantically live."* Measured
at HEAD: `PXX_KIND_TEXTSTR = 2` is declared at `builtinheap.pas:178` and a grep
excluding the declaration finds **zero writes anywhere in `compiler/`**;
`PXXStrMeta` (:391, :393) stamps `PXX_KIND_LEGACY` unconditionally from both
constructors. [[feature-nilpy-text-string-kind]] reached character-counting via
three frontend-typed helpers, so the header half was never needed.

This matters for sizing only: the implementation's first step is building the
stamping, not adding a property to a kind already being written. The decided
ticket's own guess — that the two properties are cheaper in one pass — becomes
straightforwardly true, since there is only one pass available.

### 2. A residual the decided design does not close: `None == ""`

The decided ticket notes *"`==` is unaffected: `x == ""` already answers True
correctly. It is `is None` specifically that conflates."* That holds for the
`""` direction. The other direction does not — a `-> str` def returning None,
measured at HEAD:

| | pxx | CPython |
| --- | --- | --- |
| `b is None` | True | True |
| `b == ""` | **True** | **False** |

Under the decided representation a None-str stays nil and `""` becomes a
length-0 TEXTSTR block, so a content compare still sees two zero-length operands
and still answers True. So this row survives the fix.

Per the standing instruction on the decided ticket — further string-model
questions get parked in U, not settled in passing — this is **recorded, not
decided**. It wants an answer only when someone builds the kind, and the likely
shape is that NilPy's `==` consults the meta word for a nil operand the way
`is None` will not have to.

## Disposition

Closed as already-decided. [[bug-nilpy-empty-str-and-none-are-the-same-value]]
is unblocked and is ordinary Track N work implementing the decided design; it
carries Track A's `stabilize-fast` + `make pin` obligation because it touches
`compiler/builtin/**`.
