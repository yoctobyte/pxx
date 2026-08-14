---
track: U
prio: 55
type: decide
blocked-by: []
summary: "pylib and sysutils both declare a class named Exception and the name is deliberately shared program-wide, so `except Exception:` catches either RTL's raise. The cost, measured: under `uses sysutils, pylib` pylib's OWN classes bind their ancestor to SYSUTILS' Exception, so pylib can never add a member sysutils lacks — which killed `e.args` after it had shipped. Decide who owns Exception before anything else is built on it."
status: decided
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

## 2026-08-14 — root cause found; this ticket is DOWNSTREAM of it

Track T traced the arrangement to its origin. This is not an open design
question about class ownership; it is the visible symptom of an unfinished fix.

- `ClassNameIsDeliberatelyShared('exception')` is **option 2 of
  [[decide-class-namespace-scoping]]**, landed 2026-07-28 (`c9aa7a13d`) and
  described in that ticket as *"cheap, and it is a list that will rot."*
- That decision was closed **RESOLVED-BY-CAUSE** on 2026-08-01 on the premise
  that the fork *"dissolves once [[bug-pascal-uses-is-transitive]] is fixed"*,
  with the instruction that per-site patches *"should be reverted as it lands,
  not kept."*
- **The premise never came true.** That bug was closed on its MEASUREMENT step;
  the fix was never built. Reopened 2026-08-14 at **prio 80, urgent**.

So the four options above are all ways to live with a patch that was supposed to
be temporary. **Do not pick one to "solve Exception".** Settle the root fix, and
three of the four stop being necessary.

### Measured: the "only a direct import collides" hope is false

A Pascal library with `uses sysutils` in its implementation, pulled in by a
`.npy` that never mentions sysutils, breaks exactly like a direct import once
the exemption is removed — because `uses` is transitive, so the library's
sysutils lands in the program's namespace either way. Table in
[[bug-pascal-uses-is-transitive]].

## Option 5 — rename pylib's class; `Exception` is a LANGUAGE builtin, not a library class

Raised by the user 2026-08-14, and it is the strongest argument in this ticket:

> *in python, Exception is part of the language, whereas in pascal it is a
> choice (runtime errors vs exceptions)*

That is a category difference, not a naming clash. pylib's `Exception` is the
implementation of a **Python language builtin**; sysutils' is one **library's
design choice** in a language that also offers plain runtime errors. Giving the
Python builtin a Pascal-namespace class name of `Exception` puts a language-level
concept into a library namespace where it can collide with an unrelated
library's class — and then the collision has to be papered over.

**Shape:** pylib declares `PyException`; the NilPy frontend maps Python's
`Exception` (and the builtin hierarchy under it) to it. No shared class name, no
exemption, and **pylib extends freely** — `args` lands without argument. The
bridging case (a NilPy `except Exception:` catching a Pascal raise) becomes an
explicit catch rule rather than a namespace merge, which is also the honest
description of what it actually is.

**Why this ranks above options 1-3:** it is the only one that fixes a
*correctness* problem rather than routing around a constraint, it is contained
in Track N plus one catch rule, and it does not block the root fix — when
non-transitive `uses` lands, the catch rule is the only thing left to remove.

**Unverified, and must be before committing:** that the frontend can map the
builtin name cleanly, and what it does to Pascal code doing `uses pylib` and
naming `Exception` directly — `test_uses_order_pylib_exception_a`/`_b` do
exactly that, so under option 5 those tests change meaning rather than pass, and
what they should assert instead needs deciding.

**Recommended sequencing:** option 5 now (unblocks `e.args` and everything
Python-shaped after it), [[bug-pascal-uses-is-transitive]] properly after — they
are complementary, not alternatives. The rename fixes a category error; the root
fix fixes the namespace leak.

### Option 5, implementation shape (user, 2026-08-14): do it in the LEXER

> *a small lexer fix that in any python code replaces the keyword `Exception`
> by `PyException`*

Right level, and cheaper than a semantic mapping: `.npy` source only, one token,
in `compiler/pylexer.inc`. Two properties come for free at that level —

- **string literals are safe by construction.** A lexer sees tokens, so
  `print("Exception")` is untouched. A textual pre-pass would have to care.
- **`class MyError(Exception)` maps too**, without special-casing, because the
  base-class reference is the same bare identifier.

**The one rule to get right: map the BARE identifier, not one preceded by a dot.**

```python
except Exception as e:     ->  except PyException as e:      # Python's builtin
class MyErr(Exception):    ->  class MyErr(PyException):     # ditto
import sysutils as su
except su.Exception:       ->  unchanged                     # Pascal's, qualified
```

That split is what makes the bridging case expressible instead of impossible: a
`.npy` that deliberately wants the Pascal class can still name it, qualified,
and the two stop being the same row. Worth an explicit test per line above.

Open question for whoever builds it: whether the rest of the builtin hierarchy
(`ValueError`, `KeyError`, `TypeError`, …) needs the same treatment or only the
root. They descend from pylib's `Exception` and do not collide with sysutils by
name today — but `EConvertError`-style names could collide tomorrow, and doing
the root alone leaves the family half-renamed.

## RESOLVED 2026-08-14 — option 5 built

Implemented exactly as the user specified, in the lexer.

- `compiler/builtin/pylib.pas` declares **`PyException`**; all 26 builtin
  exception classes descend from it. The class is free to grow again — nothing
  couples it to sysutils any more.
- `compiler/pylexer.inc` maps the BARE identifier `Exception` to `PyException`,
  never one preceded by `tkDot`. String literals are untouched by construction
  (a lexer sees tokens) and `class MyErr(Exception)` maps with no special case.
- `compiler/pyparser.inc`'s 18 by-name class lookups follow the rename.
- The **bridge**, which is what the "unverified, and must be before committing"
  note above was asking about: a NilPy bare `except Exception:` catches
  `PyException` AND sysutils' `Exception`, reusing the `except (A, B)` tuple
  machinery already in `PyParseTry`. Python's root catches everything a program
  can raise, and an RTL raise is still that. A QUALIFIED `su.Exception` is NOT
  that arm and stays exactly one class — which is what makes the two nameable
  apart at all.
- `ClassNameIsDeliberatelyShared` and both its call sites are **deleted**.

### What the two canary tests assert now

The open question above — "under option 5 those tests change meaning rather
than pass, and what they should assert instead needs deciding" — settled the
obvious way once only sysutils declares `Exception`:
`test_uses_order_pylib_exception_a` and `_b` must print **identical** output
(both sysutils' padded `CreateFmt`, `[    3]`). `_b`'s recorded expectation was
`[%5d]` — it was RECORDING the order-dependence as correct. The pair's whole
point is that uses order carries no meaning, and now it doesn't.

New test `test_nilpy_pyexception_bare_vs_qualified.npy` covers the four cases
the user's shape called for, one line each.

### On the open question at the end of this ticket

*"whether the rest of the builtin hierarchy needs the same treatment or only the
root"* — only the root was renamed, and that is enough: `ValueError`, `KeyError`
and friends do not collide with sysutils today, and they are reachable from a
NilPy program by their Python spelling either way. If an RTL unit ever declares
an `EValueError`-shaped collision, the fix is a per-name lexer entry beside the
`Exception` one, not a second scheme.

### Sequencing note

The user's recommended order was "option 5 now,
[[bug-pascal-uses-is-transitive]] properly after". It turned out to be not
merely preferable but REQUIRED: that ticket's gate demands
`ClassNameIsDeliberatelyShared` be deleted, and while two units declared a class
of the same name, no scoping rule could satisfy it — real scoping gives `uses
sysutils, pylib` exactly one of the two and the other's raises stop being
caught.

Commits: 6ed45773f (rename + bridge + exemption deleted), e5e90c342 (pin v294),
7f1c96a6a (tkinter's TclError, the one lib/** casualty).

**Unblocks** [[bug-nilpy-exception-args-attribute-missing]]: the constraint that
killed `e.args` — "pylib can never add a member sysutils lacks" — no longer
exists.

## Log
- 2026-08-14 — decided, commit PENDING-COMMIT.
