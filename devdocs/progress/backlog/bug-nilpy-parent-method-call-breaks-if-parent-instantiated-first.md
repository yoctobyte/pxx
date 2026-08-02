---
track: N
prio: 60
type: bug
---

# `A.call(self)` won't parse if `A` was instantiated at module level first

- **Type:** bug (NilPy frontend — loud, but wildly non-obvious) — **Track N**
- **Found:** 2026-08-02, by a differential sweep against the CPython oracle,
  then reduced by delta-debugging.

## Minimal repro

```python
class A:
    def call(self):
        return "A"

a = A()                          # <-- module-level instantiation

class E(A):
    def call(self):
        return "E:" + A.call(self)

print(E().call())
```
```
error: unexpected token
  near: E:  A  call  >>> self
```

**Move `a = A()` to after the subclass and it compiles and prints `E:A`.**
That single line, which does not mention `E` or `call` at all, decides whether
an explicit parent-method call in a later class parses.

## What is NOT the trigger

Each of these was measured working, which is what made it hard to find by
inspection:

- an explicit parent call with the method NOT overridden
- an explicit parent call with the method overridden
- a parent call inside a string concatenation
- two classes each making a parent call
- one class making two parent calls
- several sibling subclasses of the same parent
- the parent method calling `self.who()` itself
- instantiation AFTER the subclass

Only the ORDER matters: parent instantiated at module level, THEN the subclass
declaring the parent call.

## Likely cause

Instantiating `A` at module scope makes the module pre-pass bind the name `a`
and trial-parse `A()`. Something in that leaves `A` resolving as a VALUE rather
than as a class name at the later `A.call(self)` site, so the parser is at
`self` with no idea what it is looking at.

`PyAllocModuleGlobals` and the depth-0 bare-assignment TRIAL PARSE in
`PyCollectModuleLocalsAST` are the two passes that run over that line before the
class body is parsed, and both were touched on 2026-08-01/02 — worth checking
whether this predates that work by testing `stable_linux_amd64/default/pinned`
before assuming either way.

**Dump tokens before theorising** (`project_dump_tokens_before_theorising`) —
the near-text shows the parser stopping at `self`, which is a symptom, not the
cause.

## How it was found — worth repeating

Guessing at the trigger failed six times. What worked was mechanical delta
debugging: reduce the failing file line-by-line under a predicate that (a) keeps
the construct of interest present and (b) requires the candidate to still be
VALID PYTHON, so like is compared with like. Without (b) the reduction collapses
to `class A:` alone, which "fails" for an unrelated reason — that happened on
the first attempt.

## Gate

A `.npy` diffed against CPython covering the repro and its mirror (instantiation
after), instantiation of the SUBCLASS before the parent call, instantiation
inside a function rather than at module level, and a parent call reached through
two inheritance levels.
