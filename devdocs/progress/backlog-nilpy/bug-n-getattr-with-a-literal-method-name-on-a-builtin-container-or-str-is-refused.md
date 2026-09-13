---
slug: bug-n-getattr-with-a-literal-method-name-on-a-builtin-container-or-str-is-refused
title: getattr with a literal method name on a builtin container or str is refused
summary: >
  `hasattr(d, "keys")` answers True and `getattr(d, "keys")` then raises
  `AttributeError: 'TPyDict' object has no attribute 'keys'` at RUN time, while
  `getattr(s, "upper")` is refused at COMPILE time with "getattr on an attribute
  this type does not declare needs a default". Both spellings work through the
  ordinary `d.keys()` / `s.upper()` read, and both work under a COMPUTED name.
  So this is the same hasattr/getattr disagreement that
  bug-n-getattr-cannot-see-a-method-and-segfaults-through-a-dynamic-receiver
  fixed for USER classes, surviving on the builtin receivers that fix
  deliberately did not claim. It is LOUD in both forms -- a raise and a
  diagnostic, never a wrong value -- which is why it ranks below the one just
  fixed rather than beside it.
track: N
type: bug
status: backlog
prio: 45
owner: frank-user
---

## What was measured

2026-09-13, at the commit that fixed the user-class half, binary built from that
tree. CPython in the left column is the oracle, not an aspiration.

    d = {'a': 1, 'b': 2}
    s = "xy"

    hasattr(d, "keys")          CPython True   pxx True
    hasattr(s, "upper")         CPython True   pxx True
    d.keys()                    CPython works  pxx works
    s.upper()                   CPython 'XY'   pxx 'XY'
    getattr(d, "keys")          CPython works  pxx AttributeError at RUN time
    getattr(s, "upper")         CPython 'XY'   pxx REFUSED at COMPILE time:
      "Nil Python: getattr on an attribute this type does not declare needs a default"

Two different failures for one question, which is the tell that two code paths
own it. The str case never reaches run time; the dict case compiles and then
raises.

## Why the user-class fix does not cover it

That fix added an arm gated on

    atRec := ResolveNodeRec(atRecv);
    if atRec >= REC_UCLASS_BASE then ...

A dict or a str receiver is not a user class, so `ResolveNodeRec` answers below
`REC_UCLASS_BASE` and the arm correctly declines. This is a scope boundary, not
an oversight: the method predicate it uses is `FindUMeth` over a user class
index, and a pylib container method is not in those tables under that name.

`PyAttrExists` already knows how to answer the existence question for these
receivers — it has a `PyStrMethodInfo` arm and a `PyPylibMethodAlias` arm, which
is exactly why **hasattr** is right here and getattr is not. The shape of a fix
is therefore probably the same shape as the one that landed: give the literal
getattr path the same arms the hasattr half already consults, and hand the name
to a resolver that can reach a pylib method.

## Why this is not ranked higher

Both faces are LOUD. A raise and a compile diagnostic are recoverable by the
programmer; the defect just fixed was dangerous because `getattr(o, "m", None)`
returned the DEFAULT silently and the program took the wrong branch with exit 0.
Nothing here answers a wrong value, so no program can be quietly wrong because
of it.

The argument for doing it anyway is the one in the sibling ticket: hasattr and
getattr disagreeing about one name breaks the guarded idiom
`if hasattr(x, "read"): f = getattr(x, "read")`, which is ordinary Python and
which raises inside its own guard.

## Population

Not censused. The sibling's sweep of lekkerzeilen found ZERO `hasattr`->`getattr`
pairings and ZERO literal `getattr` with no default, so that package is not
exposed; no claim is made about any other.

## The family, and a shared-cause candidate

`bug-n-hasattr-with-a-computed-name-cannot-see-a-builtin-method` [p 55] is the
neighbour, and putting the four cells in one table is the reason to read them
together rather than fix either alone. Receiver is a builtin container / str:

    spelling                         pxx answer          correct?
    hasattr, LITERAL name            True                yes
    hasattr, COMPUTED name           False               NO  (the p55 ticket)
    getattr, LITERAL name            raises / refused    NO  (this ticket)
    getattr, COMPUTED name           works               yes

Two of four are wrong and they are wrong in OPPOSITE directions on opposite
axes — one spelling of hasattr is wrongly False, the other spelling of getattr
wrongly refuses. The diagonal is what suggests a shared cause: the compile-time
predicate and the runtime resolver each know about builtin methods, and each
spelling consults only ONE of them. If that is right, the fix is to make both
spellings ask both, which is the same move that fixed the user-class half
(`[[bug-n-getattr-cannot-see-a-method-and-segfaults-through-a-dynamic-receiver]]`),
and then these are one ticket and not two.

NOT VERIFIED. The table is measured; the shared-cause reading is a hypothesis,
and whoever takes either ticket should take both and find out.
