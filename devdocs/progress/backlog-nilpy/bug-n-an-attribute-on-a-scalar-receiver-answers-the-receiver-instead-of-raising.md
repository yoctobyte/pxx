---
type: bug
track: N
prio: 85
status: open
slug: bug-n-an-attribute-on-a-scalar-receiver-answers-the-receiver-instead-of-raising
---

# An attribute on a SCALAR receiver answers a garbage value instead of raising AttributeError

`i.foo` on an int answers the int. On a str it answers a RAW HANDLE as an
integer. On a float it answers 0. An attribute WRITE to None silently does
nothing. CPython raises AttributeError for every one of these.

Measured 2026-09-14 at 26249fa1d, CPython as oracle:

| expression        | CPython        | pxx                        |
|-------------------|----------------|----------------------------|
| `(5).foo`         | AttributeError | `5`                        |
| `"abc".foo`       | AttributeError | `6513249` (an internal handle) |
| `(1.5).bar`       | AttributeError | `0`                        |
| `(5).foo + 1`     | AttributeError | `6` -- flows into arithmetic |
| `None.foo = 1`    | AttributeError | silently no-ops            |

`None.foo` READ does raise correctly, which is what makes this hard to see: the
half that works is the half people probe.

## THIS IS THE UNFIXED SIBLING OF A CLOSED TICKET

`done/bug-nilpy-missing-attribute-yields-none-instead-of-attributeerror.md`
fixed exactly this defect for the CLASS-INSTANCE receiver, and pylib.pas:5010
says so in its own words: *"Reached with a receiver STATICALLY known to be a
real class instance ... never an int/str/etc scalar"*, and *"Silently answering
None instead let a typo'd attribute name travel arbitrarily far as a plausible
value before anything noticed."* That reasoning is the whole case for this
ticket, written by the person who fixed the other arm.

devdocs/dev/normalise-dont-special-case.md: fixed one arm of a double case,
grep for the sibling before closing. The sibling was not grepped for.

## WHY IT IS RANKED 85 RATHER THAN AS A DIAGNOSTIC DIFFERENCE

It is not a differing message; it is a WRONG VALUE that flows. `"abc".foo`
surfacing an internal handle as an integer is an information leak of a pointer
AND a silently wrong number in any arithmetic downstream. `(5).foo + 1 == 6` is
the shape CLAUDE.md calls the expensive kind: no crash, a plausible wrong value
far from the cause.

## FOUND FROM A REAL PROGRAM, NOT A PROBE

lekkerzeilen crashes under -dPXX_OBJTRACE with
`AttributeError: 'NoneType' object has no attribute 'grids'` at app.py:1693 --
three lines PAST the actual fault. app.py:1690/1691 do `tile.buffers = {}` and
`tile.instances = {}` on a None tile; both silently no-op, and the first
operation that cannot pretend is the method call at 1693. The traceback names
the wrong line and the wrong attribute. Found by lekkerzeilen-c8, who reasoned
from the traceback to "attribute assignment on None did not raise" and
correctly declined to claim it without a probe.

## REPRO

test/test_nilpy_an_attribute_on_a_scalar_raises_rather_than_answering_garbage.npy

## MECHANISM, from the compiler's own AST dump (not inferred)

`PXXDBG=a.ast:r_int` on `def r_int(): i = 5; return i.foo`:

```
#8196 kind=24                      <- return
  #8198 kind=11 tk=1 ival=0        <- AN_FIELD, typed INTEGER, field index 0
    #8197 kind=3  tk=13 ival=545   <- AN_IDENT, the local `i`
```

`AN_FIELD = 11` (defs.inc:708). The frontend builds a FIELD ACCESS on a scalar
receiver, resolves it to **offset 0**, and types the result as the receiver's
own type. So the generated code reads the first machine word of the receiver's
storage slot:

  - int    -> the integer itself          (`(5).foo == 5`)
  - str    -> the string HANDLE as an int (`"abc".foo == 6513249`)
  - float  -> 0
  - None   -> a write to a nil slot, discarded

There is no lookup and no failure; offset 0 always exists, which is why nothing
errors. This is the "value the BUG takes collides with a plausible right one"
class -- for an int the answer is even self-consistent under arithmetic.

## FIX DIRECTION

When the receiver's type is not a class/record and the name resolves to no
declared field, emit the AttributeError raise instead of an AN_FIELD at offset
0. `PyMakeAttrMissingCall` (pyparser.inc:2484) is the existing machinery --
already used for a missing MODULE attribute at pyparser.inc:13200 -- so this is
routing an unresolved scalar attribute to a raise that already exists, not new
runtime support.

Care needed on the positive-control side: scalar METHODS (`"AB".lower()`,
`d.get(k)`) must keep working, so the refusal belongs where the name has failed
BOTH field and method resolution. The fixture carries both control rows.

## THE FIXTURE IS DELIBERATELY NOT WIRED INTO THE MAKEFILE YET

`test/test_nilpy_an_attribute_on_a_scalar_raises_rather_than_answering_garbage.npy`
is committed as a REPRO, not as a gate. It prints `SCALARATTR FAIL` at HEAD --
that is the bug -- so wiring it now would put a known red into every lib-test
run and train readers to ignore it. Wire the row IN THE COMMIT THAT FIXES THIS,
asserting `tail -n 1` == `SCALARATTR OK`, built with `./$(COMPILER)` rather
than `$(PXX_STABLE)` since the pin will predate the fix.

Verified 2026-09-14: CPython prints `SCALARATTR OK`, pxx at 26249fa1d prints
`SCALARATTR FAIL` with all five rows failing and both positive controls
passing -- so the fixture cannot pass by a fix that raises unconditionally.
