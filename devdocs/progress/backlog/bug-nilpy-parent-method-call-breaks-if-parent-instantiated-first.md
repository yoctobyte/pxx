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

## ROOT CAUSE FOUND 2026-08-02 — it is CASE-INSENSITIVITY, not ordering

`a = A()` does not break this because of WHEN it runs. It breaks it because
`a` and `A` are the SAME NAME to pxx's resolver: NilPy inherits Pascal's
case-insensitive identifier resolution, so the instance shadows the class.

Renaming the variable to `zz` — same position, same everything else — compiles
and prints `E:A`.

So this ticket is a SYMPTOM. The real bug is
[[bug-nilpy-identifiers-are-case-insensitive]], where `x = 1; X = 2` makes
`print(x, X)` give `2 2`. Fix that and this goes with it; do NOT chase the
ordering theory below, which was my first (wrong) reading.

**blocked-by:** [[bug-nilpy-identifiers-are-case-insensitive]]

## Original (superseded) cause note

Instantiating `A` at module scope makes the module pre-pass bind the name `a`
and trial-parse `A()`. Something in that leaves `A` resolving as a VALUE rather
than as a class name at the later `A.call(self)` site, so the parser is at
`self` with no idea what it is looking at.

`PyAllocModuleGlobals` and the depth-0 bare-assignment TRIAL PARSE in
`PyCollectModuleLocalsAST` are the two passes that run over that line before the
class body is parsed.

**Checked: PRE-EXISTING, not a regression.** `stable_linux_amd64/default/pinned`
gives the identical `unexpected token` on the repro, so this predates the
2026-08-01/02 work on both of those passes. They are still the right
neighbourhood to look in — just not the cause of its appearing.

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

## Resolved 2026-08-02 — fixed by [[bug-nilpy-identifiers-are-case-insensitive]] (3ae48b3e8), no code of its own

The re-diagnosis was right and the prediction held: making NilPy identifiers
case-sensitive fixed this outright. Re-measured at HEAD, the repro compiles and
prints `E:A`.

Verified against the whole gate list in one file, byte-identical to CPython:
the repro; its mirror (instantiation after the subclass); the SUBCLASS also
instantiated under a same-cased name; instantiation inside a function rather
than at module level; and a parent call reached through two inheritance levels.

Kept as a regression test — `test/test_nilpy_parent_call_after_instantiation.npy`
(+ `.expected`, wired into `make test-nilpy`) — rather than closed silently,
because the symptom is so far from the cause: a parse error at `self`, decided
by a line that mentions neither the subclass nor the method. Every case in it
keeps the `a = A()` spelling on purpose; that is the shape that hid the bug.

## Worth keeping from this ticket

Two process notes that earned their place:

- **The delta-debugging predicate needs a validity clause.** Reducing under
  "still fails" alone collapsed the file to `class A:` — which fails for an
  unrelated reason. Adding "and is still valid Python" is what made the
  reduction compare like with like.
- **The first six guesses were wrong and the seventh measurement was right.**
  The ordering theory in the superseded section is a good record of a plausible
  story that no oracle had been diffed against.
