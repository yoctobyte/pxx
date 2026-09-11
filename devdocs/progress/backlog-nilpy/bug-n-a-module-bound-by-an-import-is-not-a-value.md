---
slug: bug-n-a-module-bound-by-an-import-is-not-a-value
track: N
type: bug
prio: 75
status: backlog
owner: ""
created: 2026-09-10
found-by: frankB
tags: [nilpy, imports, lekkerzeilen, values]
blocked-by: []
summary: "THE DESIGN FORK IS ANSWERED (2026-09-11, frankZ, last section): under the `from . import X as _backend` spelling EVERY STATIC ROW IN THE SEAM ALREADY PASSES and `getattr` over a unit alias is the ONLY construct left in lekkerzeilen/platform/__init__.py -- measured by rewriting the seam and walking the wall (`:95 _pxx` -> `_ctypes_backend.py:181` -> `:108 getattr`), not by enumerating call sites. So this needs OPTION 3 (fold `getattr(<unit alias>, \"<literal>\", <default>)` at compile time; receiver, name and miss are all decidable) and NOT a runtime module object, which no site in this corpus requires. The getattr door cannot see a unit qualifier at all today: `pyparser.inc:46680` calls ParseExpr on the receiver first, so `undefined variable (backend)` is raised before its own logic runs -- the intercept goes before that ParseExpr and `UnitDeclaresNameExactly` (symtab.inc:1117) is the non-erroring existence test. The middle wall above was a COMPILER BUG, now fixed ([[bug-n-a-dead-guarded-import-arm-still-compiles-the-module-it-imports]]), so any earlier measurement of this seam reporting a line past the end of a 150-line file was reading a dead module. AND THIS TICKET OVERSTATED OPTION 2'S COST: `_backend` appears in ONE code file; the four other modules read the seam's EXPORTED names (`from .platform import gl`), which are ordinary attributes and are unaffected by how `_backend` was bound. One file, not five. ORIGINAL REPORT: `from . import two` then `return two, \"pxx\"` -> `undefined variable (two)`. The module BINDS and `two.B` reads correctly; what fails is the bare name in VALUE position. A pxx module is a UNIT and a unit is not a first-class value, so there is nothing to push. This is the wall immediately behind bug-n-an-import-on-a-path-made-dead-by-a-failed-guarded-import-is-still-resolved on lekkerzeilen/platform/__init__.py, whose seam returns the selected backend AS A VALUE (`return _pxx, \"pxx\"`) and then reads members off the variable holding it (`gl = _backend.gl`). Both halves are needed and the second is the larger: a variable holding a module has no type today that an attribute lookup could resolve against."
---

# Measured 2026-09-10, compiler `ca814b0aabcc`, tree at `5fb6e3d57` + the dead-path fix

Minimal, and it is minimal on purpose — the package, the relative spelling and
the `try` are all removable without changing the answer:

```python
# dotpkg/__init__.py
def sel():
    from . import two
    return two, "pxx"        # <- pascal26:6: error: undefined variable (two)
```

```
near: . import two  return two >>> , "pxx"
```

lekkerzeilen/platform/__init__.py:95 is the same three tokens:

```
near: . import _pxx  return _pxx >>> , "pxx"
```

# The boundary, measured rather than guessed

| shape | result |
| --- | --- |
| `from . import two` at module level, then `two.B` | **works** |
| `from . import two` inside a def, then `two.B` | **works** |
| `from nilpy_relpkg import two`, either position, then `two.B` | **works** |
| `from . import two`, then bare `two` as a value | `undefined variable` |

So this is not about relative imports, not about packages, and not about
position. **The binding exists; it just is not a value.** Every row above but
the last was checked, which is what rules out the three explanations the error
text invites.

# Why this is two features and the second is the bigger one

The seam does both halves and neither is useful alone:

```python
_backend, _backend_name = _select_backend()   # 1. a module AS a value
gl = _backend.gl                              # 2. a member THROUGH a variable
open_window = _backend.open_window
```

1. **A module as a value.** A pxx module is a UNIT — a compile-time namespace,
   not an object — so there is no runtime thing for `return two` to push. It
   needs a module-object value, and the obvious cheap shape (a record or a
   handle naming the unit index) is only cheap until (2).

2. **A member read through a VARIABLE holding a module.** `_backend.gl` cannot
   be resolved the way `two.B` is, because `two` is a name the compiler resolves
   to a unit at parse time and `_backend` is a local whose value is not known
   until run time. That is open-world dispatch over units, and the existing
   `qualifier` door (`no member X came of the qualifier Y`) is entirely
   compile-time.

**Do not fix (1) alone.** It would make `return _pxx, "pxx"` compile and leave
`_backend.gl` to fail one line later with a different message, which is the
shape this repo keeps paying for — see the class-scope pair on 2026-09-10, where
repairing one door of two left the two disagreeing in a NEW way.

# What is NOT wanted

A special case for `return <module>` that re-resolves the name at the call site.
It would make the demo's line 100 work and would answer wrongly the moment a
module value crosses a real boundary — stored in a list, passed as an argument,
chosen by a conditional. The corpus writes all three (`_backend` is a module
global read from four other modules).

# Provenance

Found by clearing the wall in front of it. That ticket claimed to be "the LAST
wall on platform/__init__.py"; it was not, and the census could not have said so
— a first-failure census reports one error per subject and everything behind it
is invisible. Modules-compiling delta from clearing it: **0**, predicted before
the re-run and matched.

# The POPULATION, measured 2026-09-10 (frankB) — it is two sites, not a judgement

An `ast` walk over the whole lekkerzeilen corpus for a name bound to a MODULE
used in bare value position (not the base of an attribute access, not the func
of a call):

```
  lekkerzeilen/platform/__init__.py:95   _pxx
  lekkerzeilen/platform/__init__.py:97   _ctypes_backend

  files: 1   sites: 2   module bindings in the corpus: 99
```

**Two sites, one file, against 99 module bindings.** That is the number to rank
on, and it says the feature is narrow in this corpus even though it is broad in
Python.

THE FIRST CUT OF THAT CENSUS SAID 267 AND WAS WRONG, which is worth recording
because the wrong number is the persuasive one. It counted every
`from x import Vec3` name too — `Vec3(...)` is a Call whose func is a bare
`Name`, and the filter only excluded `Attribute` bases. Vec3 is a CLASS and
compiles fine. **The filter has to ask the FILESYSTEM which bound names are
modules**; nothing in the AST distinguishes `from . import world` (a module)
from `from .world import World` (a class).

# Why its RANK moved without its cause changing

This is now the FIRST WALL of `lekkerzeilen/platform/__init__.py`, because the
wall in front of it — the dead-path import (`708555fdb`) — was cleared. It was
never reachable before. `bindings.py` sits behind it too: `from . import
platform` then `platform.KEY_ESCAPE`, which is the cascade and not a second
instance.

So one fix clears **two** modules, and `platform/` is the door to the graphics
stack. The other four platform modules wall on `ctypes` independently and are
NOT unlocked by this.

# The measurement that would settle the DESIGN question

Every site here is a compile-time selection between two modules with the same
interface, which is what a unit alias is. But `getattr(_backend, "open_audio",
None)` at :112 reads a member by STRING off the variable, and that cannot be a
compile-time alias. **Whether a runtime module OBJECT is required, or whether
an alias plus a folded `getattr` covers this corpus, is one probe** — and it is
the probe that decides whether this is a table entry or a value-representation
change. It has not been run.

## THE DESIGN FORK, NARROWED TO A YES/NO — frankZ, 2026-09-10

Not taken. The ticket says part 2 is the bigger half and that is right; what
was missing is **which part 2**. Measured from the call sites rather than from
the shape of the feature, it splits, and only one half is large.

**Every use of the module-valued variable in the seam:**

    gl = _backend.gl                            static member read
    open_window = _backend.open_window          static member read
    return _backend.probe()                     static method call
    getattr(_backend, "open_audio", None)       RUNTIME getattr, with default
    getattr(_backend, "open_controller", None)  RUNTIME getattr, with default

**Three of five are statically resolvable.** A compile-time UNIT ALIAS — record
on the symbol which unit a variable was bound from, resolve `var.member`
through that unit — serves all three, is not a runtime value at all, and needs
no module object. **Only the two `getattr` sites require a real runtime module
value with dynamic attribute lookup**, and that is the large feature.

**And those two are a capability probe against a stub.** `platform/_pxx.py`
defines **neither** `open_audio` nor `open_controller`; `_ctypes_backend.py`
defines both (`:220`, `:287`). So the idiom exists to detect that the pxx
backend lacks audio and controller support, and under NilPy — where the ctypes
arm is dead — both calls always return `None`. **`_pxx.py` is the stub that
`task-b-write-the-lekkerzeilen-pxx-platform-backend` (p85) exists to write.**

So the question for whoever takes this, and it is answerable yes or no:

> **Does part 2 have to serve `getattr` on a module, or only static member
> reads?**

If only static reads: a compile-time unit alias, tractable, and it clears the
wall. If `getattr` too: a runtime module object, which is a different and much
larger feature, and one whose only two call sites in this corpus are probing a
stub that another p85 ticket is going to replace. **Ask task-b what `_pxx` will
define before building a runtime module value for two probes that may not
survive it.**

## CORRECTION — `bindings.py` is a CASCADE, not a second site

The census arithmetic lists this cause as two modules, `platform/__init__` and
`bindings`. That is correct about modules MOVED and wrong about work: `bindings`
wall is `no member KEY_ESCAPE came of the qualifier platform`, and
`KEY_ESCAPE = 27` is a **plain module constant at `platform/__init__.py:35`**.
`bindings` fails only because `platform/__init__` does not compile. One file's
construct, two modules cleared. Sixth same-line-number-family cascade in this
corpus.

## THE FORK IS NARROWER STILL — the static half ALREADY EXISTS, measured 2026-09-10 (frankZ, compiler `6d53c745ea69`)

The addendum above asked whether part 2 has to serve `getattr` or only static
member reads, and guessed that static reads would need "a compile-time unit
alias" to be built. **They do not. That alias is `import ... as`, it is in the
compiler today, and it serves every static row in the seam:**

```python
from . import fallback as backend    # or `from pkg import fallback as backend`
backend.B                            # works
backend.name()                       # works
```

Both spellings measured, module level and inside a def, and — since
`bug-n-a-dead-guarded-import-arm-still-binds-its-unit-alias` — correctly under a
`try: import ctypes / except ImportError:` guard, which is the shape that
selects a backend. So of the seam's five uses of the module-valued variable,
**three need no new feature at all**; they need the seam written with `as`
instead of with a returned value.

**What still does NOT work is exactly the two `getattr` sites:**

```python
f = getattr(backend, "open_audio", None)
#           ^ pascal26: error: undefined variable (backend)
```

A unit alias is a compile-time namespace and has nothing to push as an argument
— the same sentence as the original ticket, now with the boundary drawn one
place further in. And those two sites are the capability probe against a stub
`_pxx.py` that `task-b-write-the-lekkerzeilen-pxx-platform-backend` (p85) is
going to replace.

### So there are now THREE options, not two, and the new one is cheap

1. **Runtime module object + open-world dispatch.** Serves everything. Large.
2. **Compile-time unit alias.** Already built. Needs the SEAM rewritten to
   `from . import X as backend` — legal CPython, identical behaviour there, and
   `import ... as` is if anything the more common spelling of this idiom than
   returning a module from a function. CLAUDE.md permits changing lekkerzeilen
   where something is principally incompatible with NilPy, and a module as a
   first-class value is that. **Cost: two `getattr` probes stop working**, and
   under NilPy they already always answer `None` because `_pxx.py` defines
   neither name.
3. **Fold `getattr(<unit alias>, "<literal>", <default>)` at compile time.** The
   receiver is a compile-time unit and the name is a literal, so the answer is
   decidable — the member is in the unit or it is not. That closes option 2's
   only gap without a runtime module value anywhere. Not measured; nobody has
   looked at whether the `getattr` door can see a unit qualifier at all.

**DO NOT read option 2 as free.** It changes the corpus rather than the
compiler, and `_backend` is a module global read from four other modules — every
one of those reads has to become the alias too, or they wall on the same thing
one file further out. That is the number to get before choosing: how many of the
99 module bindings are read through a variable, not how many are used as values.

**AND THE TRAP UNDER OPTION 2 WAS REAL AND IS NOW GONE.** Written against
`73312a7472fd` — the compiler this ticket's boundary table was measured on — the
rewritten seam compiled, ran the handler, reported itself as `pxx`, and bound
`backend` to the CTYPES module, because a dead try arm still registered its unit
alias and the table is first-wins. **Silent, and in the seam whose only job is to
say which backend is live.** Fixed in `7ce61a896`; option 2 was untakeable
before it and nothing in this ticket would have said so.

## THE NUMBER THE FORK WAS WAITING ON — frankuser, 2026-09-11, compiler `35dce79343cd`, tree `bb8acc735`

The addendum above names the measurement to get before choosing option 2: *"how
many of the 99 module bindings are read through a variable, not how many are used
as values."* Run. **Five sites, ONE file**, and they are exactly the five frankZ
enumerated by hand — independent agreement from a written filter:

```
  lekkerzeilen/platform/__init__.py:102  _backend.gl              static
  lekkerzeilen/platform/__init__.py:103  _backend.open_window     static
  lekkerzeilen/platform/__init__.py:151  _backend.probe           static
  lekkerzeilen/platform/__init__.py:112  getattr(_backend, ...)   RUNTIME
  lekkerzeilen/platform/__init__.py:136  getattr(_backend, ...)   RUNTIME
```

The bare-value count came out at the same two sites frankB reported (`:95 _pxx`,
`:97 _ctypes_backend`), from a filter written independently, which is the only
reason I trust either number.

**AND THE STATED REASON OPTION 2 IS "NOT FREE" IS FALSE.** The ticket says *"`_backend`
is a module global read from four other modules — every one of those reads has to
become the alias too, or they wall on the same thing one file further out."*
Measured across the whole corpus: **`_backend` is read in exactly one file.**
Nothing outside `platform/__init__.py` names it, and nothing reads
`platform._backend` or imports it. The four other modules read the PUBLIC surface
— `gl`, `open_window`, `probe()`, `backend_name()` — which are module-level names
*assigned from* `_backend` at :102/:103 and returned at :142/:151. Those are
ordinary module attributes and option 2 does not touch them. So option 2 is
contained to one file and five sites, not spread across the corpus.

I cannot tell whether the "four other modules" line was a prediction or a
misreading of the public surface; either way it was the load-bearing objection
and it does not hold.

**OPTION 3's UNMEASURED HALF, MEASURED — and it does NOT work today.** The ticket
says *"nobody has looked at whether the `getattr` door can see a unit qualifier at
all."* It cannot, and it fails one step earlier than option 3 assumes:

```python
from . import two as backend
f = getattr(backend, "B", None)
#           ^ pascal26:3: error: undefined variable (backend)
```

The error is on the ARGUMENT, not on the lookup. A unit alias is not a resolvable
name in expression position, so there is nothing for a `getattr` handler to
receive — option 3 has to intercept `getattr(<name>, <literal>, <default>)` as a
SPECIAL FORM, before generic argument evaluation, and ask whether `<name>`
resolves to a unit alias. That is contained (one builtin call shape, receiver and
name both compile-time) but it is not the table entry the option describes.

**AND OPTION 2 ALONE DOES NOT CLEAR THE WALL, which the three-option list does not
say.** Rewriting the seam with `as` fixes :102/:103/:151 and leaves :112 and :136
failing on the same `undefined variable`. The only way to finish option 2 without
option 3 is to rewrite those two sites as direct member reads — and **that is
gated on task-b (p85)**, because a direct `backend.open_audio` cannot compile
while `_pxx.py` is the selected backend and does not define it. So:

- **option 2 + option 3** clears it now, in the compiler, no corpus dependency;
- **option 2 alone** clears it only after task-b lands the openers in `_pxx.py`.

**The yes/no the fork asked for, answered: NO runtime module object is required.**
task-b's own summary says `_pxx` will expose *"`gl`, `open_window`, `probe`, audio
and controller openers"* — so once it lands, both backends define both probed
names and the two `getattr` capability probes are **vestigial**, detecting an
absence that no longer exists. Building open-world dispatch over units for two
probes of a stub that p85 is about to fill is the wrong trade in both directions.

**Recommendation: option 3 (the `getattr` special form) in the compiler, plus the
seam rewritten with `as`.** Five sites, one corpus file, and no value
representation change. Not claimed: I have not looked at where the builtin-call
path lives, so "contained" is about the SHAPE of the change and not a diff size.

## INDEPENDENTLY CORROBORATED BY A STRONGER ROUTE — frankZ, 2026-09-11, corpus `9030d09`

The section above reaches "getattr is the only remaining construct" by enumerating
the call sites. frankZ reached it by **doing the rewrite and watching where the
wall goes**, in a scratch copy of the corpus, which is the better instrument
because it cannot miss a construct nobody thought to enumerate:

```
  seam as-is                  -> undefined variable (_pxx)        (platform/__init__.py:95)
  seam rewritten with `as`    -> _ctypes_backend.py:181           (a DEAD guarded arm; since fixed)
  dead-arm bug fixed          -> platform/__init__.py:108         = getattr(_backend, "open_audio", None)
```

Census unchanged at 23/35 before and after — **the count did not move and the
wall did**, which is the distinction a first-wall census cannot show and is why
the rewrite was worth running even though the number was flat.

So both halves of the fork are now answered from two directions that fail
differently: site enumeration (this seat) and wall-walking (frankZ). **`getattr`
over a unit alias is the only construct left in that file**, and it is decidable
at compile time — unit receiver, literal name, default present.

**One caveat frankZ volunteered against their own number, and it is the same one
this seat has:** "`_backend` is read in exactly one file" is `grep` over the
corpus and is true *of the identifier*. Neither of us has checked whether the
ticket's "read from four other modules" meant the seam's EXPORTED names instead —
which would be a different claim and an unaffected one, since those are ordinary
module attributes. Anyone acting on the containment argument should settle that
reading first; it does not change the fork's answer, only how cheap option 2 is.

**And the `_ctypes_backend.py:181` step above was a separate bug, now fixed:** a
module named by an import standing AFTER a failed one *inside the same guarded
arm* was still compiled and its errors escaped, reported with the dead module's
line number and no file name against a 150-line file. CPython never imports it.
Fixed at `PyParseImportUnitAs`. Worth knowing because it means any earlier
measurement of this seam that saw a line number past the end of
`platform/__init__.py` was looking at a dead module, not at this ticket.

## THE FORK IS ANSWERED BY MEASUREMENT, NOT BY ARGUMENT — frankZ, 2026-09-11

**Written before the two sections above landed, and they reached the option-2
correction first and by a different route.** frankuser ran a written filter over
the corpus; I read the seam and then walked the wall. The `_backend`-is-one-file
finding below is therefore NOT mine to claim — it is the same answer from two
filters that fail differently, which is the only reason either of us should
quote it. What this section adds that an enumeration cannot is the WALL WALK.

The question this ticket's earlier addendum posed —

> **Does part 2 have to serve `getattr` on a module, or only static member
> reads?**

— is now answered, and the method matters more than the answer. The earlier
attempt at it ENUMERATED the seam's five call sites and reasoned that three were
static. An enumeration can only miss what nobody thought to enumerate. This
rewrote the seam and watched where the wall goes.

**Three runs, one variable each, `lekkerzeilen/platform/__init__.py`:**

| tree | wall |
| --- | --- |
| control | `:95 undefined variable (_pxx)` |
| seam rewritten to `from . import X as _backend` | `_ctypes_backend.py:181 no member c_uint came of the qualifier ctypes` |
| + [[bug-n-a-dead-guarded-import-arm-still-compiles-the-module-it-imports]] | `:108 undefined variable (_backend)` |

Line 108 is `opener = getattr(_backend, "open_audio", None)`. So under the alias
spelling **every static row in the seam passes** — `gl = _backend.gl`,
`open_window`, `_backend.probe()` — and `getattr` over a unit alias is the only
construct left in the file. Answer: **only `getattr`, and it is option 3.**

Modules-compiling was **23 of 35 for all three runs.** The count is the wrong
readout here and the wall identity is the right one; banked separately in the
playbook as *"a flat count with a moved wall is progress the instrument reports
as zero"*.

### The middle wall was a compiler bug, not a property of the seam

`_ctypes_backend.py:181` was reported against a `platform/__init__.py` that is
150 lines long. A module named by an import standing AFTER a failed one in the
same guarded arm was still compiled. Fixed; see the ticket linked above. **Any
earlier measurement of this seam that reported a line past the end of
`platform/__init__.py` was reading a dead module.**

### What the `getattr` door can see today: nothing

Measured. `getattr(backend, "name", None)` where `backend` is a unit alias fails
with `undefined variable (backend)` raised inside `ParseExpr` on the RECEIVER —
the `hasattr`/`getattr` arm at `pyparser.inc:46680` calls `ParseExpr` first, so
its own logic never runs and never sees that the receiver is a unit. That is why
nobody had looked: there is nothing at that door to look at. The intercept has
to go BEFORE the `ParseExpr`, and `UnitDeclaresNameExactly(name, unitIdx)`
(symtab.inc:1117) is the non-erroring existence test it needs.

Both corpus sites are `getattr(<unit alias>, "<string literal>", <default>)` —
receiver decidable, name decidable, miss has a value to answer with. No runtime
module object is required by this corpus.

### CORRECTION to this ticket's stated cost for option 2

The ticket warns: *"`_backend` is a module global read from four other modules —
every one of those reads has to become the alias too, or they wall on the same
thing one file further out."* Measured at corpus `9030d09`:

- the identifier `_backend` appears in exactly ONE code file, `platform/__init__.py`;
- the four other modules read the seam's **exported** names — `from .platform
  import gl`, `from .platform import KEY_DOWN, ..., gl`, `from . import
  platform` — which are ordinary module-level attributes assigned once from
  `_backend`.

Those reads are unaffected by how `_backend` was bound. **Option 2's cost is one
file, not five.**
