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
summary: "`from . import two` then `return two, \"pxx\"` -> `undefined variable (two)`. The module BINDS and `two.B` reads correctly; what fails is the bare name in VALUE position. A pxx module is a UNIT and a unit is not a first-class value, so there is nothing to push. This is the wall immediately behind bug-n-an-import-on-a-path-made-dead-by-a-failed-guarded-import-is-still-resolved on lekkerzeilen/platform/__init__.py, whose seam returns the selected backend AS A VALUE (`return _pxx, \"pxx\"`) and then reads members off the variable holding it (`gl = _backend.gl`). Both halves are needed and the second is the larger: a variable holding a module has no type today that an attribute lookup could resolve against."
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
