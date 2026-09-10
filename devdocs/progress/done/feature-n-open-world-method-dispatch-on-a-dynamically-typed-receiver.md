---
track: N
prio: 60
type: feature
blocked-by: []
summary: "DONE 2026-09-10 (6ff12ded7). A method call on a dynamically-typed receiver whose name no declared class carries now DISPATCHES at run time instead of refusing: pydyn_meth0..4 in pyeval, emitted by PyMakeDynMethCall where PyParseVariantMethod used to Error. The closed-world scan still runs and still reports -- as a WARNING, because a closed-world warning is compatible with runtime lookup and a refusal is not. THIS TICKET'S COST ESTIMATE WAS WRONG AND THAT IS THE FINDING: it says 'there is no runtime method-lookup-BY-NAME to dispatch through' and ranked itself a feature on the strength of having to build one. There is one, complete, and in use -- every NilPy class carries an RTTI method table with each method's NAME, code address, arity and param kinds; typinfo's GetInstanceRTTI reaches it from a live instance, PyFindMethCI searches it up the parent chain, and PyHostCall marshals and invokes over it. `hasattr(A(), 'ping')` answering True on an ordinary class is the one-line probe that settles it. The compiler-side work was to CALL what the interpreter already called. A name that is not a method falls through to pydynattr_get, so a Callable field is called and a genuine miss raises pylib's existing AttributeError -- all four receiver kinds print CPython's exact wording with no new message code. MEASURED ON THE TARGET WITH A CONTROL: lekkerzeilen 9 of 28 clean -> 11 of 28, and the ROW SET moved in exactly five places and nowhere else, control = HEAD with the change stashed and rebuilt (69c0b7b47ef6) vs HEAD with it (f0bbc8603e7b). audio and wind became CLEAN; __main__, chart and environment advanced to a SECOND WALL (threading / a parse error / undefined _wind). So: five walls removed, +2 clean, and 'five modules unblocked' is not a claim anyone may make from this. A keyword argument and a fifth positional argument are REFUSED on this path rather than mis-bound or dropped, both naming the shape and pointing at annotating the receiver. --- ORIGINAL: NilPy resolves a method call on a dynamically-typed receiver by scanning the classes DECLARED IN THE COMPILATION UNIT and refuses when none declares the name -- `no class declares a method or callable field .contains()`. Ordinary cross-module duck typing therefore does not compile, which is the CPython behaviour NilPy is supposed to be upward compatible with. DIRECTION SETTLED (2026-09-09), and it follows from a written rule rather than a preference: refusing what CPython accepts is a defect for this lane. Blocks FOUR lekkerzeilen modules (chart, environment, wind, __main__), second only to math.atan2. The cost is real and it is why this is a FEATURE and not a fix: there is no runtime method-lookup-BY-NAME to dispatch through -- dispatch is a class-pointer compare against statically enumerated candidates, so with zero candidates there is nothing to emit."
status: done
owner: frankZ
---

# Open-world method dispatch on a dynamically-typed receiver

## The repro

```python
class A:
    def __init__(self):
        self.v = 1

def use(o):
    return o.ping(2)         # no class declares a method or callable field .ping()

print(A().v)
```

Seven lines. `use` is never called; CPython compiles and runs this. Reproduces
on the pin and at the tip.

## Where it bites

lekkerzeilen `wind.py:141`, `if not canopy.contains(sx, sz)`. `contains` is
declared by three classes in `world.py`, and **no module in the package imports
`world`** — the canopy is built by the importer tool and handed in. The tell is
the next line: `canopy.at(...)` resolves only because `wind.py` happens to
declare an unrelated `at` of its own. Identical call site, and the answer
depends on a coincidence elsewhere in the file. `chart.py:102`
(`tile.read_grid("bed")`) is the same cause.

## Why the direction is settled, and it is not a taste argument

**The written rule decides it.** CLAUDE.md's N lane: *"NilPy is UPWARD
compatible with CPython, one direction. Accepting what CPython rejects is a
feature."* The contrapositive is the whole of this ticket — refusing what
CPython accepts is a defect, and duck typing across a module boundary is not an
edge case of CPython's model, it is the model.

**And the closed world is not a policy we hold — it is a default we have
already conditionally abandoned.** `feature-nilpy-fallback-import` drops closed
-world dispatch WHOLESALE for any program containing an optional import that
did not resolve. So a program that says `try: import X / except ImportError:`
gets CPython semantics, and one that does not gets a compile error, **for the
identical call site**. A rule that applies except when an unrelated import
fails is not protecting anyone, and that inconsistency — not anybody's
preference — is the argument.

Direction settled by frankuser 2026-09-09 on that reasoning, ratifying a
measurement made here. It was filed as a fork; it is not one, because it is a
semantics decision about our own frontend rather than permission machinery or
anything outward-facing.

## The typo protection MOVES; it does not disappear

That objection is real and it is the reason the closed world was built. The
answer is that **a closed-world WARNING is compatible with runtime lookup; a
closed-world REFUSAL is not.** Keep the scan, keep the diagnostic, emit it as a
warning when no declared class matches, and let the call dispatch at run time.
Note the aperture was always narrow: this path runs ONLY for a receiver whose
static type is unknown, so a typo on a statically-typed receiver is caught
elsewhere and is untouched either way.

## The cost, which is why this is ranked as a feature

Half the machinery exists: `PyMakeOptionalMissingCall` already emits a call
that raises, and the fallback-import path already routes through it. What is
missing is a runtime **method-lookup-by-name** — dispatch today is a
class-pointer compare against candidates enumerated at compile time, so with
zero candidates there is nothing to emit. `getattr` does not substitute for it
and is separately broken: it sees FIELDS only, and segfaults through a dynamic
receiver (bug-n-getattr-cannot-see-a-method-and-segfaults-through-a-dynamic-receiver).

## Log
- 2026-09-10 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
