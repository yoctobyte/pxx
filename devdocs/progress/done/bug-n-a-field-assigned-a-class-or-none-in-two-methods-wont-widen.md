---
slug: bug-n-a-field-assigned-a-class-or-none-in-two-methods-wont-widen
track: N
prio: 80
type: bug
blocked-by: []
status: done
found: 2026-09-11
found-by: frankuser
owner: unassigned
summary: "ROOT-CAUSED AND FIXED 2026-09-11, and it was never about the conditional. The NilPy return-type inference walk (PyInferExprType) resolved the MEMBER token of a unit-qualified call through the GLOBAL FindProc, so any C-declared function of the same name won: lekkerzeilen's `world.open(...)` was typed by fcntl.h's `int open(...)` -- tyInt32 -- instead of by world.py's own `open`, which returns World, Region or None. tyInt32 joined against the None arm refuses, and the refusal was reported at the ASSIGNMENT several lines away, naming neither the call, the C function, nor the module. That arm was dot-aware only for a LOCAL root (PyDottedRootIsLocal); a UNIT root fell through, and the qualified arm that would have answered correctly sits LATER in the same scan -- a first-wins ordering exposed only because a header happened to declare the name. It now asks FindProcInUnit against the resolved unit first and falls back to the global, so bare calls are untouched. THE INSTRUMENT FIX IS WHAT FOUND IT, exactly as this ticket predicted: five reductions failed while the message said [a=11 b=22]; printing [a=tyInt32(11) b=tyVariant(22)] made tyInt32 read as a C int width and the sixth reduction landed immediately. Sibling still OPEN for the CALL path: bug-n-a-qualified-member-call-still-consults-the-global-c-overload-set. Regression test test_nilpy_a_qualified_member_loses_to_a_c_function_of_the_same_name, verified to fail on the pin. SUPERSEDED ORIGINAL: lekkerzeilen's entry-point closure now walls HERE: `self.world = scene if isinstance(scene, world.World) else None` in App.open_region gives `annotate the type / too dynamic [a=11 b=22]` (tyInt32 vs tyVariant). The SAME construct on the SAME field in the same class compiles ~600 lines earlier, in the ctor. Four reductions of increasing fidelity all compile and match CPython, so the trigger is NOT the conditional, the union-typed call, the None return arm, or the bound-in-ctor field shape. NOT YET REDUCED -- and the instrument that would reduce it is blind here: PXXDBG=n.locals dumps per-proc AFTER that proc compiles, so it emits nothing for the proc that failed, and a.ast:<proc> emitted nothing either. Fixing that blindness is probably the cheapest first step."
---

# A field assigned class-or-None in two methods will not widen

## The wall, and it is the current one

This is what `lekkerzeilen/__main__.py`'s closure fails on at the time of
writing, with `--threadsafe -dSDL_DISABLE_IMMINTRIN_H -dGL_GLEXT_PROTOTYPES`:

```
error: Nil Python: annotate the type / too dynamic [a=11 b=22]
  in: lekkerzeilen/app.py
  near: world . World ) else None >>>  self .
```

`a=11` is `tyInt32`, `b=22` is `tyVariant` (`compiler/defs.inc:2506`). The line is

```python
self.world = scene if isinstance(scene, world.World) else None
```

inside `App.open_region`, where `scene = load_region(name)`.

**Do not quote the line number.** It was 1195 when first hit and 1217 an hour
later, because the owner is editing `app.py` live. The construct and the method
name are the stable handles.

## The discriminator, and it is what makes this interesting

The **identical** construct, on the **same field**, in the **same class**,
compiles fine about 600 lines earlier -- in the ctor (`App.create` after
renaming):

```python
self.world = region if isinstance(region, world.World) else None   # compiles
self.world = scene  if isinstance(scene,  world.World) else None   # errors
```

So it is not the construct. Whatever differs is what `region` and `scene` are,
or an ordering effect between the two assignments.

## Four hypotheses ELIMINATED by reduction

Each of these was built and run; all four compile under pxx and match CPython,
so none of them is the trigger. Recorded so nobody pays for them twice:

1. A class-or-None conditional assigned to a local, to a `self` attribute, with
   the None arm first, and with a same-module class (no unit qualifier).
2. The non-None arm having an ambiguous/union type -- a helper returning one of
   two different classes depending on a flag.
3. A field bound from a `param=None` conditional in `__init__` and then
   reassigned from a union-typed call in a second method. This was the most
   promising model and it compiles.
4. The real shape of `world.open`, which returns THREE things -- `World(tiled)`,
   `Region(path)`, or `None`, the last via `Region(path) if path else None` --
   reached through a second wrapper, as `load_region` does.

`tyInt32` is the anomaly worth chasing. `PXXDBG=n.locals` over the whole program
shows nearly every NilPy local at `tk=22` (Variant); an Int32 here is not the
house default, so something narrowed deliberately.

## THE INSTRUMENT IS BLIND EXACTLY HERE, AND THAT IS PROBABLY THE FIRST FIX

CLAUDE.md's debugging table sends you to `PXXDBG=n.locals` for "what did the
COMPILER infer?", and for this error it answers nothing:

- `n.locals` emits its rows per-proc **after that proc compiles**. The error
  aborts `App.open_region`, so there is no row for it. Measured: 13 `App.*`
  methods dumped, `open_region` not among them, and no `App.create` row either.
- `PXXDBG=a.ast:App.open_region` emitted **zero** PXXDBG lines on the same run.

So the one tool for an inference question is silent for every proc whose
inference failed -- which is the only kind of proc anyone points it at for this
diagnostic. It does not error; it prints nothing, which reads as "no interesting
types here". Making these two dump what they have at the point of failure, or
naming the binding in the diagnostic itself, likely costs less than reducing this
bug by bisection and would serve every future instance.

## Why prio 80

It is the current wall on `umbrella-lekkerzeilen-compiles-and-runs-under-nilpy`,
which is the top-ranked goal (CLAUDE.md, goal 4). Two walls were cleared ahead of
it on 2026-09-11 (`55981bc63`, and `import threading` via the diagnostic's own
`--threadsafe` remedy), so this is what the demo is standing on now.

Standard caveat from CLAUDE.md's umbrella section: this is a FIRST-failure
report, so there is no claim about how many walls sit behind it.


## RESOLVED 2026-09-11 by frankuser

### The cause

`PyInferExprType`'s bare-call arm did `procIdx := FindProc(name)` — a GLOBAL
lookup — and that arm also fires on the MEMBER token of a qualified call. So
`world.open(...)` took its type from whatever global is called `open`, and with
any header declaring it in scope that is C's `int open(...)`.

The arm was already dot-aware, but only for a LOCAL root (`PyDottedRootIsLocal`).
A UNIT root fell straight through. The arm that resolves a qualified module
member correctly — `FindProcInUnit` — sits LATER in the same token scan, so this
is a first-wins ordering, and it was invisible until a C header happened to
declare a name a Python module also uses.

Fix: ask the unit first when the previous token is a dot and the qualifier
resolves to a unit; fall back to the global otherwise. A bare call resolves
exactly as before.

### The discriminators, all measured

| probe | result |
| --- | --- |
| `fcntl.h` (declares `open`) + module `open` | FAILS, the exact error |
| no C import | compiles, matches CPython |
| `ctype.h` (a C import with no `open`) | compiles — so it is the NAME, not C imports |
| `fcntl.h` + module member renamed `openx` | compiles — so it is the collision |

### THE INSTRUMENT FIX IS WHAT FOUND IT

This ticket's own recommendation was to fix the instrument before bisecting the
bug, and that is what happened — so the recommendation is worth trusting next
time rather than read as a consolation.

Five reductions failed while the message read `[a=11 b=22]`. `TypeKindName`
(defs.inc, beside `IntToTypeKind`) now makes it
`[a=tyInt32(11) b=tyVariant(22)]`, the ordinals deliberately kept so that months
of tickets quoting `a=11` still cross-reference. **tyInt32 is a C `int` width and
nothing in NilPy produces it** — which named the cause on sight. The sixth
reduction was written and confirmed within minutes.

Also wired, and a separate finding: `PyInferName` was DECLARED AND READ AND NEVER
ASSIGNED from the day it was written, so the `(inferring X)` half of this
diagnostic was dead text. It is now set at all five `PyWidenBinding` call sites,
the field-join included, where it prints `(inferring field world)`. That did NOT
fix this bug — the failing join is in `PyWiden` from `PyInferExprType` and carries
no binding name at all — and it is recorded as an improvement, not as the fix.

### What it unblocked

lekkerzeilen's entry-point closure moved past this wall to
`app.py: an argument after *unpacking is not supported yet` — a keyword argument
after a `*` unpack, which belongs to
`feature-n-a-call-cannot-unpack-a-sequence-into-its-arguments` and is a shape
that ticket's matrix did not cover.

### Still open, deliberately

`bug-n-a-qualified-member-call-still-consults-the-global-c-overload-set` is the
same mistake on the CALL path and this fix does not touch it. It also records
something unexplained: a hand-written `int open(const char *, int)` reproduces a
failure that glibc's own `fcntl.h` does not, and making the local declaration
variadic does not close the gap. That asymmetry is a lead, not a nuisance.

## Log
- 2026-09-11 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 54fd71123.
