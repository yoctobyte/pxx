---
track: U
prio: 60
type: decision
blocked-by: []
summary: "A compiled NilPy module inside a PACKAGE reports __file__ with the package directory COLLAPSED — `<exe_dir>/world.py` where CPython says `<root>/lekkerzeilen/world.py` — so `dirname(dirname(abspath(__file__)))`, which is how a packaged module names its repo root, overshoots by one level. Measured 2026-09-12: lekkerzeilen's runtime package has FOUR __file__ sites and ALL FOUR are that two-dirname form, all naming the same data root, and all four come out wrong; `--starts` then prints `open water: nowhere in particular` instead of listing the region, with nothing raised. This is NOT a re-litigation of decide-nilpy-dunder-file-for-a-compiled-program: that ticket never mentions packages, its rule says `<exe_dir>/<original module basename>`, and its stated payoff (`dirname(abspath(__file__))` yields the executable's directory for every module) is only reachable by collapsing the package — which is exactly what breaks the other idiom. It also deferred an application data root `until something needs it`, and lekkerzeilen is the first program that does, so its own trigger has fired. THE FORK IN ONE SENTENCE: do we want a compiled program's modules to find their data laid out the way the SOURCE tree is, or laid out the way the shipped binary's directory is? Both options are stated below with what each costs, and there is a third (a data root) the earlier decision already sketched."
---

# `__file__` for a module inside a package

## What was measured, 2026-09-12

A two-file package, binary written beside the package root — the most
favourable placement for the current convention:

```python
# mypkg/inner.py
def where():
    return (__file__,
            os.path.dirname(os.path.abspath(__file__)),
            os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
```

| | `__file__` | one dirname | two dirnames |
| --- | --- | --- | --- |
| CPython | `<root>/mypkg/inner.py` | `<root>/mypkg` | `<root>` |
| pxx | `<root>/inner.py` | `<root>` | parent of `<root>` |

**Read the whole table, not the last column.** With the package collapsed, pxx
disagrees with CPython's *shape* on **both** idioms for a packaged module: one
dirname should name the package directory and names its parent; two dirnames
should name the root and name one above it. The current convention is exactly
right for a TOP-LEVEL module (uforth, which is what it was measured on in
August) and is off by one level for every module inside a package.

## What it costs in the program that found it

`lekkerzeilen/world.py:598`:

```python
def _home(root=None):
    return root or os.path.join(os.path.dirname(os.path.dirname(
        os.path.abspath(__file__))), "world")
```

Four sites in the runtime package use that shape (`world.py` ×3, `gauges.py`
×1) and **zero use one dirname** — the single one-dirname site in the tree is
under `tests/`, which the closure does not compile. So the population in the one
real packaged program we have is 4 of 4 against the current rule.

The failure is silent and it is the house shape: `built()` returns `[]`,
`--starts` prints `open water: nowhere in particular, which is the point`, exit
code 0. Nothing raises. It is correct about open water.

## The options

1. **Keep the package directory in the virtual path** — `__file__` =
   `<exe_dir>/<pkg>/<mod>.py`. Both idioms then match CPython's shape with
   `<root>` := the executable's directory, which is the same substitution the
   August decision already makes, applied one level deeper. **Cost:** the August
   decision's payoff sentence — *"`dirname(abspath(__file__))` yields the
   executable's directory for EVERY module"* — stops being true for a packaged
   module; it yields `<exe_dir>/<pkg>`. That sentence and the four lekkerzeilen
   sites cannot both be satisfied. **Cost 2, and it is the real one:** the
   resolved source path must NOT be emitted (`defs.inc`'s own comment on
   `CompiledUnitFile` records that interning a unit path baked ExeDir into every
   binary and made our output argv0-dependent — `bug-a-the-compilers-output-depends-on-argv0`),
   so only a RELATIVE fragment may be emitted, and computing it needs a notion of
   the package root. `__init__.py`-walking from the main module's directory is
   the obvious rule and is not yet written.
2. **Leave it, and change lekkerzeilen.** The owner has licensed cheating on this
   corpus. One helper in `world.py` and one in `gauges.py`. **Cost:** it is
   idiomatic Python that works under CPython, so this is the "fix the program"
   side of the umbrella's own fork, and the next packaged program pays it again.
3. **The application data root the August decision already deferred** — a
   compile-time `--data-root=<path>` and/or a run-time override, default the
   executable's directory. Its own words: *"Not built now (user): wait for the
   first program that needs it."* This is that program. **Cost:** it does not fix
   the `__file__` shape, so a program that computes paths from `__file__` rather
   than asking for a data root still gets the off-by-one.

Options 1 and 3 are not exclusive.

## Recommendation

**Option 1.** It makes the existing rule internally consistent rather than
replacing it: the freezer frame is "paths hang off the executable's directory",
and keeping the package directory is what makes that frame produce CPython's
shape for a module that lives inside one. A frozen PyInstaller app does preserve
package structure under its own root, so the convention we chose to imitate
already does this. Option 3 is worth having afterwards and for its own reasons.

## Why this is the owner's call and not mine

The August ticket is his decision and it states the rule in words this would
change. The fork is not technical — both options are a few dozen lines — it is
about which layout a compiled program's data is expected to follow. Stated with
no implementation noun in it: **do we want a compiled program to find its data
the way the source tree is laid out, or the way the binary's own directory is
laid out?**
