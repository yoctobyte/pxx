---
track: N
prio: 35
type: bug
blocked-by: []
summary: "`d.update(other, a=1)` is a clean compile error (`unexpected token c`) — CPython accepts a mapping followed by keywords. The keywords-are-KEYS builder takes over only when the argument list STARTS with a keyword, so a positional first argument leaves the keyword run unhandled. Same for dict(other, a=1)."
status: done
owner: agent-AN
---

# `d.update(other, a=1)` — a positional argument before the keyword run

Residual of [[bug-nilpy-dict-update-keyword-args-segfault-on-two-keywords]],
whose two headline symptoms (the two-keyword segfault and the `**` refusal) are
fixed and tested. This is the row of its gate that was never built.

```python
h = {"a": 0}
h.update({"b": 1}, c=2)     # CPython {'a': 0, 'b': 1, 'c': 2}
                            # pxx      error: unexpected token  near: b >>> c
d = dict({"x": 1}, y=2)     # same shape through the other callee
```

**Not a wrong value — a clean refusal.** That is why it is priced below the
segfault it came from.

## Cause

`PyKeywordsAreKeys(mpi) and PyDictKwArgsAhead` is the guard at all five
argument loops, and `PyDictKwArgsAhead` asks whether the CURRENT token starts a
keyword or a `**`. With a positional first argument it is False, so the ordinary
argument path parses that expression and then meets `c=2` with nothing to do
about it.

## Two lowerings, and the choice is not obvious

1. **Seed the builder.** Give `PyBuildKeywordDict` an already-parsed expression
   to `pydict_merge` in before the keyword pairs. One dict argument again, so
   nothing downstream changes, and it is exactly CPython's order (the mapping
   first, keywords winning). The catch: `update` has THREE overloads
   (TPyList / TPyDict / Variant) and only the dict one can be merged this way —
   `d.update([("a", 1)], b=2)` would need the list arm, so the seed has to be
   type-directed or the mixed form restricted to a mapping seed.
2. **Two calls.** `d.update(m, **kw)` IS `d.update(m); d.update(kw)` — hoist the
   first and let the second be the expression. Handles every overload of the
   seed for free, but it puts a second call site into a construct that today is
   one, across five loops, which is the shape
   `devdocs/dev/normalise-dont-special-case.md` warns about.

Option 1 for a mapping seed is the smaller change and the one that keeps a
single call; option 2 is what a list seed would need. Worth measuring how often
the non-mapping seed appears before building the general form.

## Gate

`d.update(other, a=1)`, `dict(other, a=1)`, and the existing rows of
`test_nilpy_dict_update_keywords.npy` unchanged, all diffed against CPython.

## Resolution (2026-08-14)

Shipped. The ticket framed this as a parse gap with a lowering choice to make.
The parse gap was real and option 1 (seed the builder) was the right call — but
the thing that actually bit was the half the ticket did not mention.

**The overload half.** With the seed counted as an argument, `d.update(m, c=2)`
looked like a **two-argument** call. No `update` arm has arity 2, so the
candidate set came back empty, the caller fell through to the first-declared arm
— `update(TPyList)` — and read a TPyDict as a list: **SIGSEGV**, not the clean
refusal the ticket describes. That is the identical failure
`PyDictKwOverloadAhead` was written to remove, reached by the one shape its
lookahead did not cover: it asked whether the keyword run started at the FIRST
token after `(`, exactly as `PyDictKwArgsAhead` did. One scanner
(`PyDictKwRunFrom`) now answers for both askers.

Worth recording as method: the first build **compiled and segfaulted**, and the
crash disassembly (a 32-bit load used as a pointer, then `[rax-8]`) said
"a value read as the wrong class" long before the cause was found. The existing
note in `CountCallArgsAhead` describes this exact fall-through — the bug was
already written down, one shape over.

**The parse half.** The builder takes an optional seed, merged in before any
pair is stored, which is precisely the `**e` arm it already had — so it stays
ONE dict argument and ONE builder. Five argument loops had spelled the guard out
by hand as `PyKeywordsAreKeys(mpi) and PyDictKwArgsAhead`; the note at the first
of them already claimed "asking ONE function is how it is kept honest" and they
were not. They now ask `PyKwDictArgsHere`.

**The list seed, and why option 1's restriction was dropped.** The ticket scoped
the mixed form to a mapping seed because `pydict_merge` is typed `src: TPyDict`.
Measured: a `TPyList` passes that parameter without complaint, so
`d.update([("a", 1)], b=2)` compiled and then **segfaulted** — a silent wrong
answer where the unfixed compiler had a clean refusal, which is the one outcome
worse than the bug. The seed therefore merges through a new
`pydict_merge_any(dst; const src: Variant)` that dispatches on the object's
class exactly as `TPyDict.update(const v: Variant)` does. Both of the ticket's
lowerings are thereby moot: the general form costs one pylib routine, not a
second call site.

**Gate:** the ticket's own file, `test/test_nilpy_dict_update_keywords.npy`,
existing rows unchanged, extended with the mixed form across every receiver
shape, the list seed, a `**` spread in the same run, and a keyword belonging to
a NESTED call (which must not be mistaken for ours). Diffed against CPython.
Pinned v304 for the pylib half.

## Log
- 2026-08-14 — resolved, commit PENDING-COMMIT.
