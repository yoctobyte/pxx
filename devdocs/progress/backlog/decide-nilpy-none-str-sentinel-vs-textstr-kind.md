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
