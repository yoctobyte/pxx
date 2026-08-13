---
track: U
prio: 55
type: decide
blocked-by: []
summary: "pylib and sysutils both declare a class named Exception and the name is deliberately shared program-wide, so `except Exception:` catches either RTL's raise. The cost, measured: under `uses sysutils, pylib` pylib's OWN classes bind their ancestor to SYSUTILS' Exception, so pylib can never add a member sysutils lacks — which killed `e.args` after it had shipped. Decide who owns Exception before anything else is built on it."
---

# Who owns `Exception` — and how does pylib extend it?

Found 2026-08-13 by a Track T native-tier NEW-RED
(`test_uses_order_pylib_exception_a`) against my own `e.args` work, which had
passed every gate I ran and the pin. The feature was reverted the same night;
this ticket is the reason it cannot simply be re-landed.

## The arrangement today

`ClassNameIsDeliberatelyShared('exception')` exempts the name from
`FindUClass`'s own-unit preference. That exemption is what makes a bare
`except Exception:` in user code catch a raise from EITHER runtime — pylib's or
sysutils' — which is the behaviour both `test_uses_order_pylib_exception_a`
and `_b` exist to protect, one per uses order.

## The cost, measured

Under `uses sysutils, pylib`, while **pylib itself is being compiled**, the name
`Exception` resolves to SYSUTILS' class. So pylib's own `KeyError = class(Exception)`
descends from sysutils' Exception there, and **only members both classes have
can be reached** — from a descendant's constructor body, through a cast, from a
plain function, from anywhere.

`e.args` needed one field (`argsv`) and one method (`GetArgs`). Every spelling
was tried and every one failed in that uses order:

| spelling | result |
| --- | --- |
| `e.argsv := ...` from a pylib function | `"argsv": no such member` |
| `argsv := ...` inside `KeyError.Create` | `undefined variable (argsv)` |
| `inherited CreateWithArg(...)` (new ctor on Exception) | `inherited method not found` |
| `Exception(o).GetArgs` in the renderer | `"GetArgs": no such member` |

`Exception(o).Message` in the same renderer works — because sysutils has a
`Message` too. That is the whole rule, and it is invisible until you add the
first member that breaks it.

Removing the exemption (tried) makes pylib see its own class correctly and
**breaks the unification**: sysutils' `EConvertError` then descends from
sysutils' Exception, and a program's `except Exception:` — resolving to pylib's,
under the other uses order — stops catching it. `_b` fails at run time. So the
exemption is load-bearing exactly as designed.

## The options

1. **One class, owned by the RTL.** pylib stops declaring `Exception` and uses
   sysutils'. Anything NilPy needs (`args`, and whatever comes next) is added to
   the RTL's Exception. Clean, and it makes the unification real rather than a
   name-resolution trick. Cost: an RTL class grows Python-shaped members, and
   Track B owns that file.
2. **One class, owned by pylib**, with sysutils' Exception becoming an alias.
   Mirror image; worse, because every Pascal program pays for pylib.
3. **Keep both, and give pylib a side channel** — args stored in a pylib-level
   table keyed by the object pointer, set and read through plain FUNCTIONS
   (`pyexc_args_set`/`_get`), never through a member. It satisfies every
   constraint above, needs a release hook to avoid unbounded growth (a type test
   `o is Exception` in the release path is allowed — it is not a member access),
   and the frontend intercepts `.args` instead of a property reading it.
   This is what I would build if the classes must stay separate.
4. **Fix the resolution properly**: a unit's own declaration wins while
   compiling that unit, AND the two Exception hierarchies are unified some other
   way for `except` matching (e.g. the catch check accepts either class when the
   name is shared). Most correct, most work, and it touches `except` matching —
   the one thing you cannot get subtly wrong.

## Recommendation

**Option 1 if Track B will take it, option 3 otherwise.** Option 1 removes the
whole class of problem instead of routing around it; option 3 is the honest
workaround and is well-defined. Option 4 is the real fix and deserves its own
session with the catch path measured, not a late-night patch.

## What is parked on this

- `e.args` — [[bug-nilpy-exception-args-attribute-missing]], reopened; the
  feature is reverted, its test removed.
- [[bug-nilpy-non-keyerror-exception-args-loses-the-argument-type]] — same
  ground, cannot be attempted before this is settled.

## What survived the revert, and is worth keeping in mind

The KeyError str()/repr() fix does NOT depend on args: both construction paths
(the raise helper and a user's `KeyError(k)`) now store the message already
repr'd, because the ctor takes a Variant. Unifying the two CONSTRUCTORS settled
what an args-based renderer arm had been written to settle — one level earlier,
and it survives the uses-order constraint. Worth remembering when option 3 is
built: some of what wants `args` may not need it.

## Gate (whichever is chosen)

Both `test_uses_order_pylib_exception_a` and `_b` green — they are the canary
and they only fail in the NATIVE tier, so `gate.sh quick` will NOT catch a
regression here. Plus `e.args` correct for a KeyError with an int key, and
`except Exception:` still catching a `StrToInt` failure in both uses orders.
