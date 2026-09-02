
## 2026-09-02 (frankA) — the weak surface is ALL-OR-NOTHING, and the prefixes are not byte-identical

Two more measurements at `90b2afd68ab7`, both bearing directly on option (4).

### The 286 is a switch, not a function of what the TU uses

frankH asked the right question: is the export set fixed per object, or per unit
reached? If it grows with what the program touches, `--dce` dropping zero WEAK
bodies is the expected result and not a finding. Measured, plain `--emit-obj`:

| source | WEAK FUNC | bytes |
| --- | --- | --- |
| `int leaf(int a){return a+1;}` | **0** | 0 |
| `malloc`/`free` only | 286 | 121946 |
| `printf` only | 286 | 121946 |
| `qsort` + `strtod` + `snprintf` + `strlen` + `printf` | 286 | 121852 |

**Touch the C runtime at all and you export the whole surface**, and the NAME
SET is identical between the `printf`-only object and the wide one (`diff` over
the sorted symbol lists: no output). A TU that uses one libc function pays the
same 286 as one that uses five. So it IS the number to attack — the alternative
reading, where the set tracks usage and nothing is being wasted, is refuted.

### But the bodies behind those names are NOT identical across objects

Same 286 names, and **two of them differ in SIZE**: `qsort` 669 against 622,
`bsearch` 473 against 426, between the `printf`-only object and the wide one.
Structurally, not cosmetically — 141 instructions against 130 with different
control flow.

The trigger is smaller than "uses qsort". Defining an UNUSED static function
whose signature matches the comparator is enough; not calling it, not taking its
address, not including `<stdlib.h>`. Filed separately as
[[bug-a-an-unrelated-declaration-changes-the-emitted-body-of-a-crtl-function]],
with the four-line repro and the explicit note that **no wrong answer was
demonstrated** — both link orders sort correctly, so the variants are
behaviourally equivalent on that probe.

**What it does to option (4).** The write-up above argues that moving the
trailing tail ahead of the user's code makes the runtime prefixes byte-identical
across objects, and that "byte-identical prefixes is precisely the property
COMDAT wants". The ten shifting bytes were the known obstacle. These are a
second one, larger, of a different kind, and **no emission reorder addresses
them** — they are two different compilations of the same source. Option (4)
therefore needs one of:

- a demonstration that COMDAT's arbitrary winner is always behaviourally
  equivalent (which is what weak linking has been silently assuming since
  `243137302` — this is not a new exposure, only a newly visible one), or
- crtl codegen made independent of the user's TU, which is the ticket above.

Neither is large, and both are better answered before the writer work than
after.
