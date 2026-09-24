---
track: N
prio: 80
type: bug
blocked-by: []
summary: "RESOLVED 2026-09-24. The parameter-receiver store was already correct on origin: the commit that filed this ticket (203919198d) also routed the unpack attribute arm through PyMakeAttrStore. The same function's NAME arm did not note a rebinding to the typing pass, so a tuple target rebinding a name to another type stored raw bits or segfaulted; fixed at four doors, fixture test_nilpy_tuple_target_rebinds_a_name_across_types. Field-type widening through non-self receivers is split out."
status: done
---

## RESOLVED 2026-09-24 (frankb-12) — the store was fixed by the commit that filed this; a name-rebinding defect in the same function was not

**The summary was never true on origin.** `git log --diff-filter=A` puts this
file's creation in `203919198d`, the same commit that routed
PyUnpackTargetStore's attribute arm through PyMakeAttrStore ("ONE store
builder"). At HEAD, before any change of mine, `single/unpack/chain` through a
parameter all print CPython's `11 / 22 23 / 33 33`, and so do self, local,
module, annotated-parameter, swap, nested-receiver and starred variants.

**What the group work found instead, same function, fixed here:** the NAME
arm of PyUnpackTargetStore never noted its target to the typing pass, so a
tuple target REBINDING a name to another type kept the first slot — `x = 0;
x, y = 0.5, 1` printed 4602678819172646912 (the double's bits), and a str
local rebound by `s, n = 3, 4` segfaulted. Four doors, all fixed and all in
`test/test_nilpy_tuple_target_rebinds_a_name_across_types.npy` (CPython's
output; red on pin v420, binary sha256 af40370a8a91): the def-local note in
PyUnpackTargetStore; PyNestEmit's leaves (nested groups); the module scan,
which noted only NEW names, skipped module-level blocks (`depth = 0`), and
did not recognise a statement starting with `(` or `*`.

**Not fixed, filed:** a store of a different TYPE into a FIELD through any
non-self receiver writes the value unconverted (raw bits for a float into an
int field, single statement included) —
[[bug-n-a-store-through-a-non-self-receiver-never-widens-the-field-so-a-float-lands-as-raw-bits]].
Two refused target spellings found on the way:
[[compat-n-two-attribute-target-spellings-are-refused]].


# An unpack or chain store through a parameter receiver is silently dropped

Found 2026-09-12 while widening `PyParseChainAssign` to nested attribute targets.
Not caused by that work — the pin behaves identically.

## The measurement

```python
class A:
    def __init__(self):
        self.s = 0
        self.t = 0

def single(b):  b.s = 11;            print(b.s)        # 11   CORRECT
def unpack(b):  b.s, b.t = 22, 23;   print(b.s, b.t)   # 0 0  WRONG (CPython 22 23)
def chain(b):   b.s = b.t = 33;      print(b.s, b.t)   # 0 0  WRONG (CPython 33 33)
```

| receiver | single stmt | unpack / chain |
| --- | --- | --- |
| `self` | ok | **ok** |
| local (`a = A()` in a def) | ok | **ok** |
| module-level name | ok | **ok** |
| **PARAMETER** | ok | **STORES NOTHING** |

Pinned compiler and HEAD give the same wrong answer on the unpack row, so the
range is older than either. The chain row cannot be compiled by the pin at all
(chained assignment postdates it), which is why the unpack row is the one to
quote.

## Why it survived

**No diagnostic, and the residue is the field's initial value** — `0`, or
`False`, or whatever `__init__` set. Nothing looks wrong at the call site and
nothing looks wrong in the output unless you know the expected number.

**And the arrangement that exposes it is the one nobody writes.** A test that
exercises tuple unpacking onto attributes constructs the object in the same
function it uses it in, so the receiver is a LOCAL — which works. Passing the
object in as a parameter and unpacking onto it there is the uncommon spelling.
This is the same shape as the first-wins ordering family in CLAUDE.md: the
passing arrangements are not a sample, they are the population everyone writes.

## Where to look

`PyUnpackTargetStore` (`compiler/pyparser.inc`) resolves its receiver from
`PyProgSym(nm)` and the symbol's class identity. Compare against what the
SINGLE-statement path builds for the same source — that one is correct, so the
difference between the two receivers' resolution is the whole bug. Suspect the
parameter symbol's `RecName` being unset where a local's is set, which would send
the store to the dynamic setter while the READ stays on the declared field — the
two would then disagree exactly as measured.

**Positive control when fixing:** the table above, with the parameter row
asserted to the CPython value. A fixture using only `self`, a local or a
module-level receiver passes today and certifies the bug.

## Log
- 2026-09-24 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 3c28b6e248.
