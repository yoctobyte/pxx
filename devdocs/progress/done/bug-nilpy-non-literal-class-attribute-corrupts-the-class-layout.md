---
track: N
prio: 70
type: bug
summary: "A class attribute with a NON-LITERAL initialiser (`g = 2 + 3`) corrupts the class: a method returning a tuple of two OTHER class attributes then prints nothing or segfaults. Deleting the unused attribute fixes it"
status: done
owner: claude-AN
---

# A non-literal class attribute corrupts the class layout

- **Type:** bug (NilPy class attributes — SEGFAULT or SILENT EMPTY) — **Track N**
- **Found:** 2026-08-02, while writing the regression test for
  [[bug-nilpy-annotated-class-attribute-fails-to-parse]]. **Pre-existing** —
  reproduced against a stashed baseline build, and on the unannotated spelling,
  so neither annotations nor that fix are involved.

## Repro — three lines apart

```python
class A:
    a = 0
    d = "hi"
    g = 2 + 3            # <-- never read by anything below
    def read(self):
        return self.a, self.d
print(A().read())        # CPython (0, 'hi')    pxx: prints nothing (or segfaults)
```

Delete the `g` line and it prints `(0, 'hi')` correctly. **`g` is never
referenced** — declaring it is enough.

`2 + 3` is only an example: what matters is that the initialiser is not a single
literal TOKEN, so it takes the non-literal path. `g = []`, `g = Inner()` and
`g = f()` are the same shape.

## Where to look, and why the two branches are the suspects

`PyRegisterClassMembers` registers class attributes in **two** branches that
each call `AddUField` and each advance `curOff` independently:

- the LITERAL branch — folds the constant, types the field from the literal
  token (`tkInteger` -> `tyInt64`, `tkString` -> `tyAnsiString`, ...)
- the NON-LITERAL branch — types the field `tyVariant` (or `tyClass` for
  `Name(...)`), and `PyParseClass` evaluates the expression once into a hidden
  `$clsattr.<Class>.<name>` global that construction copies in

A class holding BOTH kinds is exactly the case where those two could disagree
about offsets or sizes — a `tyVariant` field is 16 bytes against a scalar's 8 —
and a wrong offset for the STRING attribute is consistent with what is observed
(the managed field is read from the wrong place, so the tuple build walks a bad
handle). Dump the offsets before theorising: that is a measurement, not a guess.

## The failure mode is unstable — fix against the SILENT one

The same source, rebuilt, either segfaults or prints nothing and exits 0. The
empty-output mood is the dangerous one and is the shape to fix against; the
crash is the lucky case. `-dPXX_HEAP_DEBUG` (freed bytes become `$DD` rather
than a recycled neighbour's) and `-dPXX_OBJTRACE` before any print-bisecting —
this is the "plausible wrong value far from the cause" class the debugging
playbook exists for.

## Controls that PASS — the ingredients are individually fine

| shape | result |
| --- | --- |
| the same class WITHOUT the non-literal attribute | correct |
| non-literal attribute present, method returns only `self.g` | correct |
| non-literal + container attributes, each read on its own line | correct |
| seven scalar class attributes returned as a tuple, no non-literal | correct |
| two container class attributes, no tuple-returning method | correct |
| the same values as MODULE globals | correct |
| the same values set in `__init__` as instance fields | correct |

So it needs a non-literal class attribute to EXIST and another method to build a
tuple out of the class's other attributes.

## Impact

`g = 2 + 3`, `mode = Inner()` and `items = []` at class level are ordinary
Python, and the attribute that breaks the class need not be used at all — which
makes this very hard to attribute from the symptom. A program loses a whole
tuple's worth of output with no diagnostic.

## Gate

A `.npy` diffed against CPython: the repro above; a class mixing literal,
non-literal and container class attributes read every way (individually, as a
tuple, through a method and directly on the instance); the module-global and
instance-field arrangements as controls; and the existing class-attribute tests
still green.


## Resolved 2026-08-02 — commit 7202d10e5. The title is WRONG: it was never the layout.

Kept the slug (it is what the symptom looked like), but leaving the wrong cause
in a title is how the next reader gets misled, so: **the class layout was fine
all along.** Dumping `UFldOff_`/`UFldTk` for the repro class showed
`a off=8 tk=int`, `d off=16 tk=string`, `g off=24` — correct, contiguous, and the
class size covering all three. The "two AddUField branches disagree about
`curOff`" theory in the section above is plausible and false; it is left standing
as the record of what was guessed before anything was measured.

**The actual cause was the HOIST QUEUE.** `PyParseDef` and `PyParseMethod` both
ended with `PyHoistHead := savedHoist`, meaning "drop whatever this body left
queued". That cannot unlink anything — `PySeqAppend` mutates the saved chain's
TAIL in place, so re-pointing at the head leaves the appended nodes reachable
through it. With an empty queue (`savedHoist = -1`) the restore worked by
accident, which is every case *until* something is already pending. A class
attribute with a non-literal initialiser is exactly that: `PyEmitClassAttrExpr`
queues its `$clsattr` assignment at the class statement. From then on the
method's own hoisted setup — the statements that BUILD the tuple — stayed on the
chain and were flushed into the MODULE body, where they reference the method's
locals. Hence nothing printed, or a segfault, depending on the build.

Both routines now PARK the queue on a fresh chain and restore the saved head.

### What actually cracked it

The clue was in this ticket's own control table and nearly missed: moving the
attribute BELOW the method makes the program correct. A layout bug does not care
about source order; a QUEUE does. That single re-ordering turned an unbounded
hunt into one predicted, confirmed test — and it came from varying the repro
rather than from reading the registration code, which is where the wrong theory
came from.

### Second bug, found by the same measurement and fixed with it

The member pre-pass called `g = 2 + 3` a LITERAL: it inspected only the first
token after `=`, folded the `2` and dropped the rest, while the class body's own
test (`PyClsAttrExprAhead`, which DOES check that the line ends) called it an
expression. Two readers, one construct, opposite answers — `g` was registered as
an int constant of 2 and evaluated as a global of 5. Not the cause of this bug,
but real, and fixed here: the pre-pass now requires the literal to END the
initialiser.

That is the same shape as the parameter-default constant path which claimed the
`1` of `b=1+2` (fixed earlier the same day in e53fa4a3f). **A constant fast-path
that does not check it consumed the WHOLE construct is a recurring bug in this
frontend** — worth grepping for the third instance rather than waiting for it.

### Verified

`test/test_nilpy_class_attr_hoist_leak.npy` (+ `.expected`, wired into `make
test-nilpy`), byte-identical to CPython: the repro; a list-literal attribute
(which hoists its construction); a nine-attribute class mixing literal,
expression and container initialisers with a six-element tuple return; a
literal-only control; and the non-literal attribute's own value read back as 5,
which is what catches the truncated constant-fold. Every class keeps its
non-literal attribute ABOVE the hoisting method deliberately — the ordering IS
the test.

`gate.sh quick` GREEN, self-host fixedpoint byte-identical.

## Log
- 2026-08-02 — resolved, commit 7202d10e5.
