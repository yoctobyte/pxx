---
slug: bug-n-an-attribute-on-a-dynamic-receiver-binds-to-another-class-s-field-offset
title: an attribute on a dynamically-typed receiver binds to another class's field offset
summary: >
  FIXED 2026-09-13. `v.name` where v is a variant (a dict value, a for-loop
  element, an unannotated parameter) was lowered to a DIRECT read or write at a
  declaring class's field offset, with no proof the object is that class. Two
  arms had no `is` test at all: the `sameShape` fast path, taken whenever every
  declaring class agrees on the layout -- including the common case of exactly
  ONE declaring class -- and the LAST candidate, used as the else arm of the
  dispatch. The second also swallowed every declaring class past the sixteenth,
  because PyVariantFieldCands stops collecting at PY_MAX_FIELD_CANDIDATES and
  says nothing. A read answers another class's slot; the write twin STORES over
  it, and for a Variant-typed field the store first releases whatever the
  foreign bytes decode to, which segfaults. Both halves now `is`-test every
  candidate and fall back to pydynattr_get_v / pydynattr_set_v, which resolve
  by the RTTI of the class the object actually is.
track: N
type: bug
prio: 85
owner: frank-user
status: done
---

## How it was found

Attempting the lekkerzeilen umbrella. With the previous wall cleared
(`bug-n-a-callee-declared-below-its-caller-gets-the-argument-by-the-wrong-abi`)
the compiled demo reached `gauges.py:366` and stopped at

    Unhandled exception: TypeError: expected a number, got function

on `floor = pound.level - drop`. The probe that named the defect is the one
that compares an INSIDE read against an OUTSIDE one:

    PROBE pound=          Pound(1, 6.54, 'Neder-Rijn')     <- __repr__, correct
    PROBE pound.id=       1                                <- correct
    PROBE pound.observed= None                             <- correct
    PROBE pound.name=     <a memory dump>                  <- wrong
    PROBE poundlevel=     <function at 0x3032325f36395f74> <- wrong

`Pound.__repr__` reads `self.id`, `self.now` and `self.name` from INSIDE the
class and prints all three correctly, so the object is intact and only the
DYNAMIC read is wrong. `0x3032325f36395f74` decodes little-endian as the ASCII
string `t_96_220` -- a tile id belonging to no Pound -- so the read was landing
outside the object entirely.

Five standalone reductions failed before the mechanism was found, because each
of them happened to put the interesting class where it passes.

## The reduction

Eighteen lines, and it segfaults:

    class Ghost:
        def __init__(self):
            self.keep = 1

    class Pound:
        def __init__(self, name):
            self.name = name or ""

    def stamp(o):
        o.name = "ghostly"

    g = Ghost()
    stamp(g)
    print("done")

`Pound` is never instantiated. `o` is an unannotated parameter, so a variant;
exactly one class declares `name`; the frontend stores into Pound's layout at
Pound's offset. `PXXDBG=a.ir:stamp` shows the whole defect in one line --
`field a=5 ival=8 tk=22` then `var_store`, a direct store at offset 8 with no
test before it.

`self.name = name or ""` versus `self.name = name` is the difference between a
SEGFAULT and silent corruption, and it is not the bug: the `or` widens the
field to Variant, and a variant store RELEASES the old value first. With the
field typed AnsiString the same store just writes over `Ghost.keep` and the
program carries on. The crashing spelling is the lucky one.

## The cap, which is the same defect with a different door

`PyVariantFieldCands` collects into `TPyFieldCands`, sized
`PY_MAX_FIELD_CANDIDATES = 16`, and drops the rest silently -- `n` does not
count them. So the seventeenth class declaring a name was not merely
mis-ordered, it was invisible, and the unchecked last-candidate arm answered
for it. Measured with generated files, one field name, each class putting it at
a different offset:

    16 classes -> all 16 correct
    17 classes -> the seventeenth segfaults, the other sixteen correct
    20 classes -> classes 17..20 all die, the first sixteen correct

lekkerzeilen reaches this easily: `name` is declared by Route, Furniture,
Pound, Region, Reading, the traffic and rig classes and more.

With the dynamic fallback in place the cap is no longer a correctness limit at
all -- a class past the sixteenth simply resolves at run time instead of
through an inline arm -- so it is left at 16 rather than raised.

## The fix

`compiler/pyparser.inc`, `PyMakeVariantField` (read) and
`PyMakeVariantFieldSet` (write): the else arm is now always
`PyMakeDynAttrGet` / `PyMakeDynAttrSet`, and every candidate keeps its own
`is pyvarobj(v)` test. The `sameShape` fast path is gone and the write no
longer declines names with fewer than two candidates. `PyVariantFieldHasPropCarrier`
is removed -- it existed to pick the dynamic fallback for property carriers,
and the fallback is unconditional now.

The read and the write must take the SAME rule about which names dispatch, or
the caller rewinds into the read and the IR refuses the ternary as an
assignment target (`IR_UNSUPPORTED: frontend could not lower AST node (kind
67)`). That is recorded in the code, because it is not visible from either
function alone.

## What it costs

lekkerzeilen's code segment goes 11300520 -> 12521128 bytes, +10.8%, for the
extra `is` tests. Not measured for speed; the arms themselves are unchanged and
the dynamic call runs only when no candidate matches, which for correct code is
never.

## What is still open

The write's dynamic fallback uses `pydynattr_set`, which is store-only, so a
@property SETTER on a dynamically-typed receiver is still skipped --
`bug-nilpy-property-setter-is-skipped-on-a-dynamically-typed-receiver`, already
filed. That is strictly better than the arm it replaced, which wrote into
another class's layout.

## Verification

- `test/test_nilpy_an_attribute_on_a_dynamic_receiver.npy`, 3 sections, CPython
  the oracle. The control rows are the arrangement everyone writes.
- Seven reproducers from the hunt, all matching CPython after the fix and all
  measured identical on pin v408 before it.
- `tools/gate.sh quick` GREEN, full `make test-nilpy` green.
- The demo clears `gauges.py` entirely and stops two walls further in.

## Log

- 2026-09-13 | fixed in `compiler/pyparser.inc`, commit e5cd18e4b. Closed by the
  same commit, which also carries the `max(genexp, default=)` wall behind it and
  `struct.Struct`.
