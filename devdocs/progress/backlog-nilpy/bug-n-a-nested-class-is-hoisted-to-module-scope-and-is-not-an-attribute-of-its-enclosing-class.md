---
slug: bug-n-a-nested-class-is-hoisted-to-module-scope-and-is-not-an-attribute-of-its-enclosing-class
title: a nested class is hoisted to module scope and is not an attribute of its enclosing class
summary: >
  Measured 2026-09-13 at 7990405c2. `class Outer:` with `class Bare:` in its body
  registers `Bare` as a MODULE-level name and not as a class-level attribute of
  `Outer`. Every spelling is exactly backwards from CPython: `Bare.V` compiles and
  answers 5 where CPython raises NameError, and `Outer.Bare.V` -- the spelling
  CPython accepts -- is REFUSED at compile time with
  `error: class method not found: Bare`. The accepted half is upward
  compatibility and fine by Track N's rule; the refused half is the bug. A nested
  class is a compile-time refusal, so it cannot produce a wrong value at run time
  and nothing silently misbehaves.
track: N
type: bug
prio: 45
owner: unassigned
status: open
---

## The measurement

Three rows, one file, compiler `7990405c2`:

```python
class Outer:
    class Bare:
        V = 5
    def m(self):
        return 1

print("A", Outer().m())     # pxx 1        CPython 1
print("B", Bare.V)          # pxx 5        CPython NameError
print("C", Outer.Bare.V)    # pxx REFUSED  CPython 5
```

Row C:

    pascal26:9: error: class method not found: Bare
      near: ( "C" , Outer . Bare >>> . V )

Drop row C and the program compiles and prints `A 1` / `B 5`.

## What is actually wrong, and it is not the hoisting

The nested class IS parsed and IS registered -- at the wrong scope. So this is a
placement bug, not a missing feature: nothing needs to learn how to parse a class
inside a class body, and the machinery that builds the class already ran.

Accepting `Bare` at module scope is upward compatibility (CLAUDE.md, Track N:
NilPy is upward compatible with CPython, one direction) and needs no change.
**What must be added is the class-level binding**, so `Outer.Bare` resolves.
Whether the module-level name then goes away is a separate question and the
answer is probably no, since removing it can only break programs that compile
today.

## The diagnostic is correct about something else

`class method not found: Bare` is the house failure mode in one line. The lookup
that ran was a METHOD lookup, because a nested class is not registered as a
class-level attribute of any kind -- so the resolver reached the only class-level
door it has and reported truthfully about that door. A reader chasing "method"
looks at method registration, which is working. Whoever takes this should start
at the class-member registration in `PyRegisterClassMembers` / `PyParseClass`
and ask where a nested `class` statement's result is bound, not at method lookup.

## Ranking, and why it is not higher

Low reach, measured rather than assumed. lekkerzeilen uses indented `class`
statements only under `tests/`, and those are mostly function-local classes,
which is a different construct. No module in the demo's import graph reaches
this. It is a compile-time refusal, so it cannot join the silent-wrong-value
population that earns a p70+ in this lane.

## What this ticket is NOT

An earlier session (this one, pre-compaction) carried a claim that a class whose
body contains a nested class loses its own method-default evaluation, via
`PyClsEvalCi`/`Lo`/`Hi` being clobbered by the recursive `PyParseClass`. **That
does not reproduce** and is not filed: with a nested class present, with and
without methods on the nested class, `Outer().m()` still evaluates its default
correctly and answers 7. The three globals ARE an implicit return channel from
`PyParseClass` to its caller and the recursion does overwrite them -- so the
mechanism is real and the observable is not. Anyone who rediscovers the globals
should measure before filing; that is the whole reason this section exists.
