---
track: U
prio: 60
type: decision
blocked-by: []
summary: "STATE 2026-09-22: DECIDED, BUILT AND LANDED as `dbeb993a2` on origin/master (sha read off origin AFTER the push, not from a pre-push log -- this repo rebases nearly every sync and the local sha was bef116001, a ghost). The HOW-TO-TELL paragraph below is kept rather than deleted because it was written before the landing and is now ANSWERED: CurUnitPyRel is on origin/master, so the arm it describes as LOST did not happen. Option 1 (put the package directory in the virtual path). NOT ESCALATED, and that is itself the decision: the fork as stated had an arm that is not an intent, since option 1 keeps the binary's-directory frame exactly and only applies it at the level CPython uses, so what it costs is the August decision's PAYOFF SENTENCE -- true of every module that existed when it was written, because none were in a package -- and not a decision. Three standing rules then decide it, chiefly that NilPy is upward compatible with CPython in ONE direction, which makes code running correctly under CPython and wrongly under us a BUG rather than a compat item. decide-nilpy-dunder-file-for-a-compiled-program is NOT overruled or edited; this EXTENDS it to a case its text never mentions. HOW TO TELL WHAT ACTUALLY LANDED, because this line is written from a working tree and not from a commit: if this ticket is still in working/, `git log --oneline -- compiler/defs.inc | head` and grep the tree for CurUnitPyRel -- present means the fix landed and only the resolve is missing, ABSENT means the seat was cut off before banking and the implementation is LOST, not half-done, because it lived in one uncommitted working tree. GREP THE RIGHT TREE, AND THE PATH IS /home/neo/frankH: there are ~20 sibling checkouts on this box, each with its own compiler/, so a grep that finds nothing is AMBIGUOUS between "lost" and "wrong checkout" unless the path is named. If it landed it is on origin/master and every checkout has it after a pull, which is the cheaper check: `git log origin/master -S CurUnitPyRel -- compiler/defs.inc`, which is a ref-level question and answers correctly from anywhere. In that case the design above still stands and the build is ~1 hour: a new global beside CurUnitDir carrying the package-relative virtual path, set where the unit is parsed, plus ONE shared PyEmitDunderFile replacing the byte-identical copies in pyparser.inc and pasparser_expr.inc. AND THE NON-OBVIOUS HALF, which cost the most to find and is what a re-derivation will miss: the old answer DEPENDED ON IMPORT ORDER -- a dotted import registers the mangled `pkg_inner` and a relative one the bare `inner`, whichever compiles the file FIRST wins via the resolved-path dedupe, so the same module in the same program reported `<dir>/pkg_inner.py` or `<dir>/inner.py` depending on statement order and neither matched CPython. That reframes the ticket: not "our convention differs by one level", which a project may legitimately choose, but "the same source gives different answers depending on import order", which is not a convention. A fixture must therefore import the package BOTH WAYS ROUND -- under the pinned compiler the single-spelling arrangement is IDENTICAL on the basename row and would certify half the defect. A compiled NilPy module inside a PACKAGE reports __file__ with the package directory COLLAPSED — `<exe_dir>/world.py` where CPython says `<root>/lekkerzeilen/world.py` — so `dirname(dirname(abspath(__file__)))`, which is how a packaged module names its repo root, overshoots by one level. Measured 2026-09-12: lekkerzeilen's runtime package has FOUR __file__ sites and ALL FOUR are that two-dirname form, all naming the same data root, and all four come out wrong; `--starts` then prints `open water: nowhere in particular` instead of listing the region, with nothing raised. This is NOT a re-litigation of decide-nilpy-dunder-file-for-a-compiled-program: that ticket never mentions packages, its rule says `<exe_dir>/<original module basename>`, and its stated payoff (`dirname(abspath(__file__))` yields the executable's directory for every module) is only reachable by collapsing the package — which is exactly what breaks the other idiom. It also deferred an application data root `until something needs it`, and lekkerzeilen is the first program that does, so its own trigger has fired. THE FORK IN ONE SENTENCE: do we want a compiled program's modules to find their data laid out the way the SOURCE tree is, or laid out the way the shipped binary's directory is? Both options are stated below with what each costs, and there is a third (a data root) the earlier decision already sketched."
status: decided
owner: frankh-c0
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

## DECIDED 2026-09-22 (frankh-c0): option 1, and NOT escalated. Here is why.

I am taking this rather than sending it up, and the reason is the one CLAUDE.md
predicts: *"writing it usually reveals that an existing rule already decides
it."* This ticket did the hard part — it states the fork as a sentence about
what we want, with no implementation noun in it — and stating it that well is
what shows the fork is not a fork.

**THE STATED FORK HAS AN ARM THAT IS NOT AN INTENT.** The sentence is *"do we
want a compiled program to find its data the way the SOURCE tree is laid out, or
the way the BINARY'S directory is laid out?"* Option 1 does not choose the first
arm. It keeps the binary's-directory frame exactly — `<exe_dir>` substitutes for
`<root>` — and applies it at the level CPython uses. Under option 1 a packaged
module's `__file__` is `<exe_dir>/<pkg>/<mod>.py`, which is the August rule
unchanged, read one level deeper. The two arms are not two intentions; one is
the intention and the other is where a sentence written without packages in mind
happens to land.

So what option 1 costs is not an intent. It is the August ticket's **payoff
sentence** — *"`dirname(abspath(__file__))` yields the executable's directory for
EVERY module"* — which was true of every module that existed when it was
written, because none of them were in a package. That is a claim with a date on
it, not a decision.

**AND THREE STANDING RULES DECIDE IT, none of which needed the owner:**

1. **NilPy is UPWARD compatible with CPython, one direction.** Accepting what
   CPython rejects is a feature; code that runs correctly under CPython and
   wrongly under us is a **bug**. Four sites in one real program, silently
   wrong, is the bug side of that line and not a compat item.
2. **"Real code compiling or running wrong is a bug."** `--starts` prints `open
   water: nowhere in particular` and exits 0. Nothing raises.
3. **The goal list names lekkerzeilen as a demo.** Option 2 makes the demo
   depend on a patched copy of the program, which is the "fix the program" arm
   the umbrella's own fork exists to refuse.

**WHAT I AM NOT DOING:** I am not editing or overruling
`decide-nilpy-dunder-file-for-a-compiled-program`. That is the owner's decision
and it stands. This extends it to a case it does not mention — its own text
never says "package" — and I will say so in its Log rather than rewriting its
rule.

**REVERSIBILITY, which is the actual test.** This is a few dozen lines in two
lowering sites plus a fixture. If the owner reads it and wants the collapsed
path back, it is one revert. A big reversible change is mine; a small
irreversible one would not be. Reported rather than asked.

**WHAT WOULD MAKE ME WRONG:** a real program that relies on
`dirname(abspath(__file__))` naming the executable's directory *from inside a
package*. The population we have is 4 of 4 the other way, and the single
one-dirname site in the tree is under `tests/`, which the closure does not
compile. If someone finds such a program, that is evidence and this should be
re-opened on it — not on the argument that the August sentence said so.

**Option 3 (the data root) is not closed by this** and remains worth having on
its own terms; options 1 and 3 are not exclusive, as the ticket says.

## MEASURED 2026-09-22: it is not an off-by-one, it is IMPORT-ORDER DEPENDENT

The ticket's table records one value for pxx, `<root>/inner.py`. There are
**two**, and which one you get depends on the order of two import statements
elsewhere in the program.

Two-file package, one module, two mains differing only in the order of their
two imports:

    # a_dotted_first.py            # b_rel_first.py
    import mypkg.inner             import mypkg.sib      # sib does `from . import inner`
    import mypkg.sib               import mypkg.inner
    print(mypkg.inner.where())     print(mypkg.inner.where())

| | `__file__` of `mypkg/inner.py` |
| --- | --- |
| pxx, dotted import first | `<dir>/mypkg_inner.py` |
| pxx, relative import first | `<dir>/inner.py` |
| CPython, either order | `<dir>/mypkg/inner.py` |

**The same module in the same program reports two different `__file__` values,
and neither matches CPython.** The `mypkg_inner.py` spelling is the worse of the
two: it is a filename no file ever had, with an underscore where CPython has a
separator, so `basename` is wrong as well as `dirname`.

**Mechanism.** The unit name is mangled dots-to-underscores at
`pyparser.inc:47335` (`PyConsumeDottedModule`) and again at `pyparser.inc:47783`
(`PyPackageSubmoduleKey`), so a dotted import registers the unit as
`mypkg_inner`; a relative `from . import inner` passes the bare `inner`. Whichever
spelling compiles the file FIRST wins, because the second one hits the
resolved-path dedupe at `pasparser_proc.inc:6886-6925` and becomes an alias
without re-parsing — so `__file__` is lowered exactly once, from whichever name
got there first.

**This is the first-wins hazard CLAUDE.md names**, and it is a textbook
instance: *"a first-wins table is exposed only by the arrangement that puts the
correct entry last."* The ticket's original measurement took the relative arm,
which produces the tidy-looking `inner.py` and reads as a clean off-by-one. The
dotted arm produces a mangled name and does not read as an off-by-one at all.
Both were reachable from the start; only one was measured.

**What it changes.** Nothing about the decision — option 1 fixes both arms,
because both should produce `mypkg/inner.py`. What it changes is the ARGUMENT:
this is no longer "our convention differs from CPython's by one directory
level", which is the kind of thing a project may legitimately choose. It is
"the same source produces different `__file__` values depending on import
order", which is not a convention at all. The fix must therefore be at the point
where the fragment is COMPUTED, not a post-hoc adjustment of the mangled name —
unmangling `mypkg_inner` is ambiguous anyway, since a module may legitimately
contain an underscore.

**Population and oracle, recorded so a re-run is comparable:** one two-file
package plus one sibling module, `mypkg/{__init__,inner,sib}.py`, built with
`compiler/pascal26` at 5f986d67044a, oracle CPython 3 on the same tree,
executable and package both under one `mktemp -d`.

## Log
- 2026-09-22 — decided; this names the commit that carried the decision, which is not always the one that carried the change — commit 4ecca09ec.
