
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

## 2026-09-02 (frankC + frankA) — the ticket got BIGGER by 46 bodies per object, and it is a correctness fix that did it

Recorded here because it changes the size this ticket is about, and because the
way it was nearly missed is the reusable part.

`9e7c4cf8c` — *static on a C function is internal linkage, so the object writer
emits it LOCAL* — moved **46 crtl symbols from GLOBAL/WEAK to LOCAL**
(`__crtl_alloc_file`, `__crtl_atoa`, the `__crtl_dexp_*` family, `gr_parse`,
`pw_parse`, `exec_collect`). Their bodies total 65682 bytes. A LOCAL body cannot
be deduplicated by any linker, so 82 objects keep 82 copies:
`65682 * 81 = 5320242` bytes, about 72% of the 7.3MB the busybox separate build
grew by between 2026-09-01 and today. The remaining ~2MB is unchased.

**That is the price of correct linkage, not a regression.** `static` in C IS
internal linkage and LOCAL is the right binding; there is nothing here to revert
or bisect toward a culprit. What it does is make this ticket's problem larger and
better founded — 46 more bodies per object that no linker may merge is exactly
N×crtl, arriving from a direction nobody planned — and option (4)'s COMDAT group
now buys these back too. The argument that only a mechanism running where the
winner is known can reach these bytes applies to LOCAL bodies unchanged, and
more forcefully: a LOCAL body is not merely *pinned by* an export contract, it is
invisible to the linker as a candidate at all.

**Two measurements of two different quantities, both correct.** I bounded the
window at **≤0.35% growth per OBJECT** (a TU pulling every crtl header:
626536 → 628728, FUNC count identical at 1089) and concluded the growth was not
the compiler. frankC reproduced that bound exactly (+0.27%) and then showed what
it cannot see: `busybox_diff.sh:1105` reports `stat -c%s "$out"` — the **LINKED
BINARY**, where 82 objects interact. **Changing a symbol's BINDING does not
change its object's size at all**; it changes whether the linker may collapse 82
identical copies into one. My instrument was aimed at the object and the effect
lives in the link.

The endpoints were also never commensurable, which is why not bisecting was
right: the recorded 27765544 transcript has no `sha256=`, no `compiler=` and no
per-TU flags line — all of which today's script prints — and its oracle line says
`gcc unity build` where today's says `gcc separate build, 82 objects`
(`268e1e83c`).

### The current numbers, all one script, one config, one day

| per-TU flags | 82 objects linked | |
| --- | --- | --- |
| `--emit-obj` | 35131104 | |
| `--emit-obj --dce` | 29563696 | `--dce` saves **15.85%** |

Both GREEN, 154/154 byte-identical to the gcc oracle, at compiler
`89cf8ea39628` — at or above `cf4281b6a`, so the callback-shadowing miscompile
is not in these builds.

### And the shadowing caveat is discharged for busybox specifically

crtl's shadowable function-pointer parameter names are `cmp`, `f`, `func`,
`init_routine`, `proc`, `start`. **No busybox TU defines a file-scope function
with any of them** — zero across the whole tree, a superset of the 82 built —
positive-controlled against names that must hit (`main` 33 TUs, `bb_error_msg`
1) and one that must not (`cmp_cb` 0), cross-checked with a looser pattern whose
four extra hits were all comments. The stated limit is that a regex cannot see a
definition produced by macro expansion.
