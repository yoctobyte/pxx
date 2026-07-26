---
summary: "Pascal: a duplicate class declaration silently binds to the earlier one instead of erroring"
type: bug
track: P
prio: 50
---

# Pascal: a second class with the same name is not diagnosed

- **Type:** bug (Pascal frontend, class registration / diagnostics) — **Track P**
- **Status:** backlog
- **Opened:** 2026-07-26.

## This ticket REPLACES a wrong one

It was filed as `bug-pascal-subclass-inherited-members`, claiming four ways
subclassing was broken: inherited fields and methods invisible unqualified, the
inherited constructor resolving to a different `Create`, and the inherited default
property losing subscript assignment. **That report was wrong** and the file is
deleted rather than left to mislead.

What actually happened: implementing `collections.Counter` I declared
`TPyCounter = class(TPyDict)` in `compiler/builtin/pylib.pas` — where **`TPyCounter`
already exists** (pylib line 46, the `itertools.count` iterator). Every symptom was
that collision:

- `indexof` / `FVals` "undefined" — the method bodies bound to the EXISTING
  TPyCounter, which descends from nothing and has neither.
- "not enough arguments to constructor TPyCounter.Create (parameter start has no
  default)" — that is literally the existing `TPyCounter.Create(start: Int64)`.
  The message was telling me the truth and I read it as constructor inheritance.
- `c[k] = v` not parsing — the existing class has no default property.

Subclassing itself works. Verified after the fact, both in a program and in a unit,
and inside pylib against TPyDict: a bare inherited method call, a bare inherited
field read, an overriding method, a re-declared `default` property with subscript
ASSIGNMENT, overloaded methods, and the inherited constructor all behave.

## The real (smaller) bug

Declaring a class whose name is already taken should be an ERROR naming the
collision. Instead the second declaration is accepted and uses of the name bind to
the first, so the diagnostics land far away — in a 4000-line unit that is a long
detour, and it cost real time here.

Note `collections.Counter` shipped as a MODE on TPyDict rather than a subclass
(commit d40a8410). That decision no longer has a technical justification, only a
practical one: as a mode, a Counter IS a dict, so subscript/items/iteration/`dict(c)`
came along free. Worth revisiting only if Counter needs to diverge further.

## Gate

`make test` + self-host byte-identical, with a `test/` case asserting the duplicate
declaration is rejected and names the earlier one.
