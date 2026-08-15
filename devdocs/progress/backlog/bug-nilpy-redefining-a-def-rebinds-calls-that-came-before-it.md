---
track: N
prio: 35
type: bug
blocked-by: []
summary: "Redefining a `def` makes calls written BEFORE the redefinition run the LATER body. `def q: 'first'; print(q(1)); def q: 'second'; print(q(2))` prints second/second where CPython prints first/second. Silent wrong value on a valid CPython program, and there is no diagnostic — the name resolves once, statically, to the last definition."
---

# Redefining a `def` rebinds the calls that came before it

- **Type:** bug (silent wrong value) — **Track N**
- **Found:** 2026-08-15, and found the hard way: an appended test block reused a
  helper name the file already had, and the EXISTING rows above it started
  printing binary garbage
  ([[bug-nilpy-star-unpack-that-would-fill-a-fixed-parameter]]). Reproduced on
  `pinned`, so it is pre-existing and independent of that work.

## Repro

```python
def q(a):
    return "first:" + str(a)
print(q(1))            # CPython first:1     pxx second:1
def q(a):
    return "second:" + str(a)
print(q(2))            # CPython second:2    pxx second:2
```

No diagnostic. The name resolves once, statically, to the LAST definition in
the module, so every call site — including the ones lexically above the
redefinition — targets it.

## Why it is worse than it reads

With the same signature it is a wrong VALUE. With a **different** signature it
is memory corruption: the case that surfaced it had

```python
def g(x, *rest):
    return str(x) + "|" + str(rest)
print(g(1, *xs))       # bound, at run time, to the LATER g...

def g(x, *rest):
    return x, rest     # ...which returns a TUPLE, not a str
```

and the earlier call — compiled expecting a string result — printed several
kilobytes of raw memory. So the failure mode is not bounded by "you get the
other function's answer".

## In scope under the upward-compatibility rule

Redefinition is ordinary CPython that runs to completion and observably differs,
so this is not the "laxer than CPython is a feature" case
(`devdocs/dev/nilpy-semantics-divergences.md`). It is the mirror of
[[project_nilpy_trial_parse_rolled_back_symbol_index_recycled]]'s family: one
NAME, two bindings, and the frontend keeps only the last.

## Shape a fix probably takes

NilPy names are resolved statically, so the fix is at DEFINITION time, not call
time: a second `def` of an existing name should allocate a NEW proc and rebind
the name from that point in the parse forward, leaving already-parsed call sites
pointing at the first. That is how the shadowing rules elsewhere in this
frontend work, so the machinery is likely present.

Worth checking in the same pass whether a `class` redefinition, and a `def`
that shadows an imported name, have the same shape.

## Gate

`.npy` diffed against CPython: same-signature redefinition with calls on both
sides; different return TYPE (the corrupting case above); a redefinition inside
a branch that does not execute; and a `class` redefined the same way. Per-fix
loop.
