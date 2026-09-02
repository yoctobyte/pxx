
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

**CORRECTION, 65682 IS THE DELTA AND NOT THE RESIDUAL** (frankC, same day).
Measured on one object: today's total LOCAL body bytes are **173823**, of which
the 46 newly-LOCAL account for 65682 and 108141 were already LOCAL before
`9e7c4cf8c`. The pinned object's LOCAL total is exactly 108141 — today minus the
46 — which is the cross-check that makes the attribution believable rather than
merely arithmetically available. So **the per-object un-mergeable residual is
~174KB of LOCAL plus the ~21KB weak surface**, and `9e7c4cf8c` raised it by 61%
rather than creating it. Every "~21KB per object" figure earlier in this ticket
is the WEAK half only and was never the whole residual.

**AND THERE IS NO LEFT EDGE TO TAKE.** `--separate --pinned` on today's script
is RED: *82 objects did not link*, on `multiple definition of abort, abs,
accept, access, addmntent, ...`. `9e7c4cf8c` did two things in one commit —
made `static` emit LOCAL, and removed `-Wl,-z,muldefs` from the harness link on
the strength of that. A compiler from below it cannot build this mode at all, so
any `--separate` size compared across that boundary compares two LINK MODES
rather than two compilers. The commensurability question is closed in the
strongest available way: not "the endpoints are hard to align" but "the older
endpoint cannot produce the artefact". (Those duplicate names are crtl's PUBLIC
surface, not the 46 internals — a different population, so it is a second
mechanism and not the same one seen twice. The list is `head -10` truncated, so
ten is a sample and not a count.)

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

## 2026-09-02 (frankA) — step 2's prerequisite is down to FIVE named relocations

`b098c63c6` closed the third of the three open questions above (`ProcAddrFix`
relocating against the `.text` section symbol, which was true for options (2)
and (4) alike). With calls, `@proc` and VMT slots all naming symbols, the
question "what still binds `.text` together" is now answerable by enumeration
rather than by reading, and the answer is small. Measured at `89cf8ea39628`,
`--emit-obj --function-sections`:

| | `.rela.text` | `.rela.data` | `.rela.init_array` | `.rela.fini_array` |
| --- | --- | --- | --- | --- |
| `test_emit_obj.pas` | **0** of 624 | 3 of 84 | 1 of 1 | 1 of 1 |
| a one-line C program | **0** of 2782 | 0 of 5 | 1 of 1 | 1 of 1 |

counting entries that name the `.text` SECTION symbol. **Code-to-code references
are fully relocated: zero in `.rela.text`, in both frontends.** Five entries
remain in the Pascal object and two in the C one, and they are these:

```
.rela.data        R_X86_64_64  .text - 1        (x3)
.rela.init_array  R_X86_64_64  .text + 1aae4
.rela.fini_array  R_X86_64_64  .text + 1ab06
```

- **The init and fini thunks** are the two the park already names, and the park
  also records why they are not a clean tail: both fall INSIDE the removable
  range of whatever proc precedes them, which is a different proc in every
  program. They are already registered as DCE stub targets, so the machinery to
  track them exists; what they need is a symbol to relocate against.
- **The three `.text - 1` entries are VMT slots for interface methods with no
  body in this object** (`MethodFix ... baked 3 (first: IInterface.QueryInterface)`).
  The addend is `BodyAddr = -1`, so these slots do not merely resist relocation
  — they name `.text` minus one byte. Harmless today only because nothing
  dispatches through them here; worth its own look before anyone relies on the
  count being three.

**A fourth blocker the table does not show, because it is not a relocation.**
The C object reports `CallFix 1087 relocated 1081 pinned-target 6`. Those six
are the shape `ObjCallFixIsRelocatable` deliberately refuses — a call site whose
recorded target disagrees with its proc row, which happens when a C file has two
same-named file-scope statics and the later body overwrites the row. They stay
baked, and a baked displacement is computed for this object's own copy of the
callee, so **per-function sections cannot land while any of them do.** They are
counted rather than assumed absent, which is what makes them findable; six is a
number to attack, not a footnote.

So the honest statement of the remaining work for step 2's first half is: give
the init/fini thunks symbols, decide what an interface-method VMT slot should
relocate against, and eliminate the six pinned-target call sites. None of those
is a design question.

## 2026-09-02 (frankA) — the thunks have symbols; two of the five are gone

`.rela.init_array` and `.rela.fini_array` now name `__pxx_init_thunk` and
`__pxx_fini_thunk`, LOCAL FUNC symbols in `.text`, with addend 0. Under
`--function-sections` only, so the default object is byte-identical (verified by
sha256 against one built before the change).

That leaves **three** entries in a Pascal object and **zero** in a C one still
bound to the `.text` section symbol — the three interface-method VMT slots whose
`BodyAddr` is `-1`.

**The verification method had to change, and that is worth reading before
touching either test.** 4a-bis and 4a-ter asserted the LINKED BINARY was
byte-identical with the flag on and off, which was the right assertion for a
flag with no observable effect. Adding two symbols gives it one: the file grows
88 bytes, and the account is exact — 2 × 24 bytes of `Elf64_Sym` plus 34 bytes
of names is 82, plus 6 of padding. **None of it is executable or readable by the
program.** Both blocks now compare every allocatable section individually via
`tools/elf_alloc_same.sh` and additionally assert the symbol delta is EXACTLY
those two names with nothing removed — stronger than `cmp`, which could only
have said "differ".

`elf_alloc_same.sh` carries two guards it needed on its first run:

- **It counts what it compared and fails below a caller-supplied floor.** The
  first version extracted sections with `objcopy`, compared them, and printed
  `identical` having compared ZERO — the extraction silently produced nothing
  and the loop body never ran.
- **`LC_ALL=C` on both the `sort` and the `comm`.** Without it, `comm` warned
  "file 1 is not in sorted order" on stderr, printed a 60-name added list and a
  59-name removed list of the SAME symbols, and exited 0.

**Poison control, run:** changing the init-array addend 0 → 8 makes
`.init_array` differ AND turns the program's output from `done99 pxx-emit-obj`
into `done`. So for the thunks BOTH instruments discriminate, where for the VMT
slots only the byte-compare does — recorded in the test, because the two
families sit in one block and neither instrument covers both.

**One limit stated rather than discovered later:** the thunk symbols carry SIZE
0, because a thunk is code no proc owns and its extent is recorded nowhere.
That is fine for a relocation, which wants an address. It is NOT fine for
`--gc-sections`, which wants a size, so whoever builds step 2's second half owes
these two a real extent.

## 2026-09-02 (frankA) — the last three were a live bug, and the object was where it printed

The three `.rela.data` entries still naming the `.text` section symbol read
`.text - 1`, and the minus one is the whole finding. Every writer resolves a
VMT/RTTI method slot as `entry + Procs[p].BodyAddr`, and a routine with no body
has `BodyAddr = -1`. The slot ends up holding **the address one byte below the
entry point** — inside the image, plausible, and dereferenced the first time
anything calls through it.

**It is not an `--emit-obj` artefact.** The ordinary executable carries the same
value; the object is just where the arithmetic is printed instead of folded.
Measured with the pre-fix compiler `787639bf0c8d`, words equal to `entry - 1` in
a linked binary: `test_emit_obj` 3, a probe with one abstract method 5, a probe
with two interfaces 27.

**Two populations have no body, both by declaration and both normal:** an
INTERFACE method (`IInterface.QueryInterface` and its two siblings were the three
here) and an ABSTRACT method (`TStream.Read`). The recording site guards on
`procIdx >= 0`, which asks whether the routine is KNOWN — it is, with a real
signature that the arity and param-kind fields read legitimately — when the
question is whether it has CODE.

`DropBodilessMethodFixups` (emit.inc) drops those fixups once, at the single
point where all code is emitted and DCE has run, just before the writer
dispatch. So `MethodFixCount` is already right for the four object writers that
size `.rela.data` from it and the six loops that resolve a slot, and **none of
them needed to change** — the alternative was six sites and four counts kept in
agreement by hand.

| after the drop, `test_emit_obj --emit-obj --function-sections` | |
| --- | --- |
| `.rela.text` naming `.text` | 0 |
| `.rela.data` naming `.text` | **0** (was 3) |
| `.rela.init_array` / `.rela.fini_array` | 0 / 0 |

**Step 2's first half is done: nothing in a Pascal object names the `.text`
section symbol.** What remains is giving the per-function sections real
extents — including the two thunk symbols, which still carry SIZE 0.

**Two things tried and rejected, both recorded because they look right:**

- **An error instead of nil.** The @proc sibling refuses a bodiless routine at
  link time and that is correct there; here it refused every program that uses
  `TStream`. `nil` is what typinfo's `GetMethodAddr` documents as its only "no
  address" answer, and it is what the slot already holds.
- **A relocation against the null symbol.** Spells the same nil, but leaves an
  entry in `.rela.data` for a slot with no target — under `--function-sections`
  the point is that nothing names what it does not mean.

**Reachability, since it decides whether this is a bug or bookkeeping.** The
abstract case is reachable from ordinary user code: `GetMethodAddr(cls, 'Abs1')`
returned a non-nil pointer to `entry - 1`, and the new test calls the concrete
sibling through the same API as its control. The interface case is NOT reachable
from a program — an interface's RTTI blob is deliberately absent from the class
registry (measured: `GetClass('IInterface')` answers nil) — which is why the
interface half is asserted on the object, in the Makefile, and not by a probe.
