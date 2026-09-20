---
slug: feature-n-dataclass-frozen-true-needs-a-store-guard-not-an-acceptance
title: "@dataclass(frozen=True): the work is the store guard, not the acceptance"
track: N
type: feature
prio: 40
status: backlog
owner: ""
created: 2026-09-20
found-by: frankH
tags: [nilpy, dataclasses, frozen, diagnostic]
blocked-by: []
summary: "MECHANISM: `@dataclass(frozen=True)` is refused by name, and the refusal is CORRECT as it stands -- PyParseDataclassArgs says in its own comment that silently accepting it would hand back a class that looks immutable and is not, a silent wrong answer in place of today's loud one. So the work is NOT deleting the refusal; the generated __init__/__eq__/__repr__ are already what a frozen dataclass needs, and the ONLY thing frozen adds that we lack is that a store to a field must RAISE. THE HOLE A COMPILE-TIME GUARD LEAVES IS THE ONE TO DESIGN FOR: a store through a receiver whose class is statically known can be refused at compile time, but a store through a VARIANT-held instance cannot, and that is exactly the shape real code has (an instance pulled out of a dict or list is a variant here -- measured separately on shape.py). A guard that catches the easy half and silently permits the hard half is the same silent-wrong-answer the current refusal exists to prevent, so the acceptance should land WITH a runtime store check, not before it. Second-order: frozen also makes a dataclass HASHABLE in CPython (eq=True, frozen=True generates __hash__), so a program may legitimately use one as a dict key or set member -- accepting frozen without that is a different silent gap."
---

# frozen=True: the refusal is right; the store guard is the work

Found 2026-09-20 (frankH) censusing That Space Program under NilPy.

Two TSP files wall on this and they are **one site**: `director.py:37` and
`provider.py:37` report the same line number, `frozen=True` appears only in
director.py, and provider.py imports it. The diagnostic is printing an imported
module's line number with no file name.

The class is `director.Shot` — a plain value record, constructed by three small
helpers and read, never mutated. Every program that respects frozenness would
run correctly against the ordinary generated class, which is what makes
"just accept it" so tempting and so wrong.

**Do not delete the refusal on its own.** Its reasoning in `PyParseDataclassArgs`
is exactly this tree's rule about loud-becoming-silent: the class would look
immutable and would not be, so a program that mutates one gets no diagnostic
from us where CPython raises `FrozenInstanceError`. Today's error is loud and
names the gap.

Design notes for whoever takes it:

- The compile-time half is easy and partial: refuse a store to a field of a
  class marked frozen wherever the receiver's class is statically known.
- The runtime half is the one that matters, because an instance held in a list,
  a dict or a comprehension target is a VARIANT here, and that is the ordinary
  shape of real code. The dynamic attribute STORE path is where the check
  belongs.
- `frozen=True` with the default `eq=True` also generates `__hash__` in CPython,
  so a frozen dataclass may be used as a dict key or a set member. Accepting
  frozen without hashability moves the gap rather than closing it.
