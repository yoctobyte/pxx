---
prio: 55
track: N
type: bug
status: backlog
owner:
blocked-by: []
summary: "A class defining one ordinary method twice compiles, then SEGFAULTS when the method is called. CPython rebinds and the last definition wins. Pre-existing — identical on the pre-fix pinned binary and on the fix for the duplicate-method HANG, so the two are different defects sharing one source shape."
---

# Calling a duplicated ordinary method segfaults

Found while writing the regression test for
`bug-n-a-class-with-two-definitions-of-one-method-hangs-the-compiler-forever`.
I put this shape in that test, and it crashed for a reason that had nothing to do
with the hang — so it is filed rather than folded in.

## Repro — 10 lines, complete

```python
class D:
    def m(self, prefix):
        self.prefix = prefix

    def m(self, other, prefix):
        self.prefix = prefix

d = D()
d.m("p", "q")
print(d.prefix)
```

```
CPython   -> q
pxx       -> compiles clean, then SIGSEGV (rc=139), no output
```

## Not the hang, and not caused by its fix — measured both ways

| binary | result |
| --- | --- |
| `stable_linux_amd64/default/pinned` (pre-fix) | compiles, run rc=139 |
| the duplicate-method-hang fix (`SymHashBkt`) | compiles, run rc=139 |

Identical on both, so this is **pre-existing** and the hash-bucket fix neither
caused nor cures it. It is also a different failure *class*: the hang needed three
ingredients including a later scope holding a bare same-named local, and produced
no binary at all. This one has **no third scope**, compiles clean, and dies at
run time — which makes it the quieter of the two and the one that would survive a
suite that only asserts on compiler exit status.

## Why it is a bug rather than NilPy laxness

CPython *accepts* this source — a re-`def` rebinds and the last definition wins —
so a program CPython runs correctly crashes here. That is the upward-compat
direction that Track N's rule says is a defect, not the direction it excuses.

## Where to look

Both definitions survive registration rather than the second replacing the first
— the hang ticket's trace shows two `n.ret def@` rows for one name — so a call
plausibly binds the arity/signature of one definition and the body or frame of
the other. The two definitions here have **different arities** (2 vs 3 including
self), which is the obvious first thing to vary: check whether two
same-arity definitions also crash, and whether the surviving `d.prefix` write
lands through the wrong frame.

## Gate

`make compiler/pascal26` + this repro printing `q`, and add it to
`test/test_nilpy_duplicate_method_def.npy`, which currently carries a comment
saying this shape is deliberately absent because it crashes.
