---
track: N
prio: 60
type: bug
owner:
blocked-by: []
summary: "`if flag: def pick(): return 7` / `else: def pick(): return 9` inside ONE function answers 9 for BOTH branches -- CPython gives 7 and 9. SILENT, exit 0, no diagnostic. Two same-named nested defs in one function collapse to one proc and the call resolves by POSITION, so a call after the if/else takes the LAST definition whatever ran. It is loud only when the arities DIFFER (`no overload of outer.pick$29 matches`), which is the already-closed method-collision case; when they MATCH -- the idiomatic shape, since exclusive branches naturally define the same signature -- it is a wrong value. Sequential rebinding in one function is CORRECT (`def pick` ... `def pick` answers 7 then 9), so this is specific to defs the program treats as alternatives. DISTINCT from bug-nilpy-same-named-nested-defs-in-two-methods-collide (two METHODS, loud, done) whose own note records that two plain FUNCTIONS do not collide -- one function was never tested. Cousin of bug-n-a-def-inside-a-taken-branch-does-not-rebind-the-name at module level, where the same source shape is REFUSED instead: conditional definition is broken at both scopes, differently."
status: open
---

# Two same-named defs in exclusive branches of one function collapse silently

## Repro

```python
def outer(flag):
    if flag:
        def pick():
            return 7
    else:
        def pick():
            return 9
    return pick()

print(outer(True), outer(False))
```

    CPython   7 9
    pxx       9 9          exit 0, no diagnostic

Measured at compiler `a41d8ac34eb9`.

## The boundary

| shape | CPython | pxx |
| --- | --- | --- |
| exclusive branches, **same arity** | `7 9` | **`9 9`** silent |
| exclusive branches, **different arity** | `7 9` | REFUSED, `no overload of outer.pick$29 matches` |
| sequential rebind in one function | `(7, 9)` | `(7, 9)` correct |
| single def inside a `for`, called in the loop | `[0, 10, 20]` | `[0, 10, 20]` correct |
| single def inside a `try` body | `7` | `7` correct |

**The silent row is the idiomatic one.** Two arms of an `if`/`else` defining
the same function naturally give it the same signature — that is the whole
point of the construct. The arity-mismatch row is an accident of writing the
example carelessly, and it is the only row that announces itself.

**Sequential rebinding being correct** is what rules out "one name, one proc"
as the whole story: the call there resolves to the nearest preceding
definition. In the branch shape both defs precede the single call site, so the
LAST one wins regardless of which branch executed — consistent with position
based resolution and no notion of a branch being exclusive.

## Why this is not the closed method-collision ticket

[[bug-nilpy-same-named-nested-defs-in-two-methods-collide]] is two METHODS of
one class, is **loud**, and is done. Its own closing note says:

> *"two nested defs of the same name in two plain FUNCTIONS do NOT collide ...
> so this is specific to methods."*

True, and **two same-named defs in ONE function was never tested.** That note
is the reason this shape had no ticket: it reads as having cleared the
function case.

That ticket also says **"Loud, which is the good case — it is a compile error,
not a wrong value."** This is the same family arriving as the bad case.

## Relationship to the module-level ticket

[[bug-n-a-def-inside-a-taken-branch-does-not-rebind-the-name]] is the same
SOURCE SHAPE at module scope, where it fails differently: `PyRegisterDefShells`
walks at depth 0 only, so a module-level def inside a branch is never
registered at all and the program is REFUSED (`unresolved forward`). Inside a
function, defs in branches ARE registered and then collapse.

**So conditional definition is broken at both scopes by different mechanisms**,
and a fix for either leaves the other. Worth holding together when either is
taken; not merged, because the mechanisms are genuinely different and one
ticket claiming both would mis-state at least one of them.

## Found by

Answering tuxspaceprogram-c6's scan question about function-local defs under
compound statements (2026-09-20). **Its own two sites are NOT affected**: each
is a SINGLE def inside a `for`, which is the correct row above. The defect
needs two same-named defs the program treats as alternatives.

Those sites are in the **tuxspaceprogram** repo, not this one, and are
deliberately described by SHAPE rather than by file and line. Two reasons, and
the first is this ticket author's own rule from the same evening: a citation
into another repo's tree is not something a pxx seat can resolve, and it is not
something a pxx seat can keep true either. The second is measured — c6's own
first scan of those files mistook a same-named closure in a different scope for
one of them, so **even the owning repo found the coordinates harder to keep
straight than the shape.**

## Gate

`outer(True), outer(False)` answers `7 9`. The sequential-rebind row still
answers `(7, 9)`, and the arity-mismatch row must not start silently picking
one — if it cannot be made to work it should stay loud.
