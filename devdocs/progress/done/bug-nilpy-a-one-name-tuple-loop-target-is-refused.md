---
track: N
prio: 25
type: bug
blocked-by: []
summary: "`for (x,) in pairs:` — a one-name PARENTHESISED loop target with a trailing comma — is refused. Python unpacks the 1-tuple; a single-name target here would bind the whole element, so this needs an unpack, not just comma tolerance."
status: done
owner: agent-AN
---

# A one-name tuple loop target is refused

```python
for (only,) in [(1,), (2,)]:
    print(only)          # CPython: 1 then 2
```

pxx now says:

    a one-name tuple loop target (`for (x,) in ...`) is not supported yet —
    write `for x in ...` if the element is not a 1-tuple, or unpack in the
    body if it is

Found while landing [[feature-nilpy-starred-and-nested-unpacking]]'s nested
targets, and split out because it is a DIFFERENT gap that happened to share a
diagnostic. Not caused by that work — the parenthesised-target path is
untouched by it.

## Why it is not just comma tolerance

The obvious fix — let the target list end on a trailing comma — is wrong. With
one name and no group, the for lowering binds the ELEMENT to that name, so
`for (only,) in [(1,)]` would bind `only` to the tuple `(1,)` and print
`(1,)`. Python unpacks the 1-tuple, so this needs a one-element unpack, which
is the same index-unpack the nested-target work added — the parenthesised-target
scan just consumes the `(` before that machinery is reachable.

Likely shape of the fix: let `PyParseForTargetSlot` own the whole parenthesised
group instead of the pre-scan stripping the parens, so a trailing comma makes it
a group of one and the existing body prologue unpacks it.

## Why the priority is low

Real code writes `for x in xs` or `for a, b in pairs`. `for (x,) in ...` shows up
mostly in generated code and in `zip()`-of-one. The diagnostic now names the
form and says what to write instead, which is the part that mattered.

## Gate

A `.npy` diffed against CPython covering `for (x,) in [(1,), (2,)]` and the
neighbouring forms that already work (`for (x) in xs`, `for (a, b) in pairs`).

## Resolution (2026-08-15)

`for (only,) in [(1,), (2,)]` binds 1 then 2, as CPython does.

**The ticket's diagnosis and its suggested shape were both right.** Two edits,
in the two places the ticket names:

- **The pre-scan stops stripping the parens when the group ends with a trailing
  comma.** `for (a, b) in xs` has meaningless parens and is still stripped;
  `for (only,) in xs` is a 1-tuple unpack, and stripping its parens is exactly
  the wrong answer the ticket warns about — it would bind the whole element to
  `only`. Detected by looking at the token before the matching `)`, which the
  scan already walks to.
- **`PyParseForTargetSlot` accepts a ONE-name group when the comma is there.**
  Its loop now breaks on a trailing comma and remembers it, so `n = 1` is legal
  exactly when the source said `(x,)` and still refused otherwise ("a nested
  loop target needs at least two names" is what `for (x) in ...` should get).
  Everything downstream is untouched: a one-name group is `PyForNestCount = 1`
  and the body prologue's index-unpack handles it like any other arity.

The trailing comma is legal on a longer group too (`for (a, b,) in ...`), and
falls out of the same change.

**Gate:** `test/test_nilpy_nested_loop_target.npy` extended in place — the
one-name tuple target, the same nested beside another target, a trailing comma
on a two-name group, and the two controls that must NOT change (a comma-less
group still has its parens stripped, and a single bare name still binds the
whole element). Byte-identical to CPython; `.expected` refreshed.
`tools/gate.sh quick` GREEN, self-host byte-identical.

## Log
- 2026-08-15 — resolved, commit 310f02341.
