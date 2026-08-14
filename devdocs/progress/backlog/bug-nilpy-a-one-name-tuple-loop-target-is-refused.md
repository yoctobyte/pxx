---
track: N
prio: 25
type: bug
blocked-by: []
summary: "`for (x,) in pairs:` — a one-name PARENTHESISED loop target with a trailing comma — is refused. Python unpacks the 1-tuple; a single-name target here would bind the whole element, so this needs an unpack, not just comma tolerance."
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
