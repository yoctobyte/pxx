---
track: N
prio: 60
type: bug
blocked-by: []
summary: "NilPy dispatches a method call on a dynamically-typed receiver by scanning every class DECLARED IN THE COMPILATION UNIT, and refuses outright when none declares the name: `no class declares a method or callable field .contains()`. Ordinary cross-module duck typing therefore does not compile -- the object's class lives in a module this one never imports, which is the normal Python arrangement and the whole point of duck typing. Blocks FOUR lekkerzeilen modules (chart, environment, wind, __main__), the largest cause after math.atan2. The closed world is deliberate and is what catches a typo on a variant receiver, so this is a FORK, not a one-line widening: the machinery for the other answer already exists (PyMakeOptionalMissingCall, feature-nilpy-fallback-import) but there is no runtime method-lookup-by-name to dispatch through."
status: backlog
owner: —
---

# A duck-typed method call is refused when no class in the unit declares the name

## The repro

```python
class A:
    def __init__(self):
        self.v = 1

def use(o):
    return o.ping(2)         # no class declares a method or callable field .ping()

print(A().v)
```

Seven lines. `use` is never called; CPython compiles and runs this happily.
Reproduces on the pin and at the tip.

## Where it bites in real code

lekkerzeilen `wind.py:141`:

```python
canopy = self.canopy          # a ctor parameter, so a variant
if canopy is None:
    return 0.0
...
if not canopy.contains(sx, sz):
```

`contains` is declared by three classes in `world.py`, and **no module in the
package imports `world`** -- the canopy is built by the importer tool and
handed in. That is duck typing working exactly as intended. `canopy.at(...)`
on the next line resolves only because `wind.py` happens to declare an
unrelated `at` of its own, which is the tell: the call site is identical and
the answer depends on a coincidence elsewhere in the file.

`chart.py:102` is the same shape (`tile.read_grid("bed")`).

## The fork, and why it is not a one-line widening

The closed world is a designed property, and `pyparser.inc` says so where it
excludes the optional-import case: *"Closed-world dispatch stays a compile
error for every program WITHOUT such an import ... so typo detection is
unchanged there."*

- **Keep it** and the umbrella needs the source changed instead -- importable
  in principle (the owner has licensed source changes here), but it is not a
  *principal* incompatibility, it is the language's core dispatch model.
- **Open it** and a typo on a variant receiver becomes a runtime AttributeError
  rather than a compile error. Note the aperture is already narrow: this path
  runs ONLY for a receiver whose static type is unknown. A typo on a
  statically-typed receiver is caught elsewhere and is unaffected.

Half the machinery is there. `PyMakeOptionalMissingCall` already emits a call
that raises, and `feature-nilpy-fallback-import` already abandons the closed
world wholesale for any program with a failed optional import -- so a program
that says `try: import X` gets CPython's semantics today and one that does not
gets a compile error, for the identical call site. What is missing is a
runtime method-lookup-BY-NAME: dispatch is a class-pointer compare against
statically enumerated candidates, so with zero candidates there is nothing to
emit. That is a feature, not an aperture change.

## Measured beside it

`getattr(o, "ping")()` does not substitute for it and is separately broken --
see bug-n-getattr-cannot-see-a-method-and-segfaults-through-a-dynamic-receiver.
