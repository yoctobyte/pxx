---
slug: decide-a-is-a-pxx-object-a-self-contained-runtime-or-a-translation-unit
track: U
prio: 55
type: decide
status: backlog
created: 2026-09-02
found-by: frankC
owner: ""
blocked-by: []
summary: "MEASURED 2026-09-18 (frankB) AND THE FORK COLLAPSES TO ONE SENTENCE FOR THE OWNER: **do we promise that a pxx object can supply the runtime for SOMETHING ELSE, or only for ITSELF?** Answer \"for itself\" and B is safe today. Answer \"for something else\" and A stands and per-object DCE stays off the table until the runtime is shared. Evidence: `--dce` does not move the export surface at all (307 weak FUNC exported both ways; the exports ARE the root set, so the pass can only remove 266 LOCAL bodies) -- so B had to be simulated, off the object's own relocations, with the compiler's 573-live answer as the positive control (model: 576). Re-rooted at the TU's own two exports, live bodies go 576 -> **78** -- the number this ticket already records for the same code as an executable, reproduced from a different direction -- and **298 of 307 weak exports vanish**. 20 of the 298 are routines a backend LOWERS onto and no source names (`__pxx_builtin_popcount*`, `__pxx_va_arg_agg`, ...), demonstrated: a second TU containing zero `__pxx_` in its source reaches `__pxx_va_arg_agg` by passing a struct by value through a variadic. **So B's contract change is not source-auditable.** BUT the pxx-to-pxx pair is NOT at risk: both objects have ZERO undefined symbols of any kind, because each carries everything it reaches -- the parent ticket's own complaint is what makes B safe between pxx objects. The silent breakage is confined to a NON-PXX consumer, or to the `libcrtl.a` direction where one object provides the runtime for the rest -- both of which are the self-contained-runtime reading, i.e. answer A's premise. Nothing is recommended; x86-64 only, a Pascal object and 4b-septies' DATA symbols are unmeasured and the page says so. IMPORT SIDE, separately: `ld` errors on relocation SITES, not on undefined symbol-table entries -- an xtensa object's ESP-IDF UND entries sit at 20 with and without `--dce` while relocations naming them go 24 -> 0 and the link goes rc=1 -> rc=0. So \"the symbol goes, not just the bytes\" is false on the import side and the benefit arrives without it."
---

# Is a pxx object a self-contained runtime, or a translation unit?

## The fork

`ObjProcIsExported` is `ProcCdecl and not ProcCStaticLink`, and **every crtl
routine satisfies it**, because crtl is C and C functions are cdecl and
non-static. So an object's export surface is its whole runtime.

That was free until a pass started deleting things. Measured at `60edd4853`
(one C TU, two exported functions, using `snprintf`/`malloc`/`strlen`):

| | bodies live | bytes |
| --- | --- | --- |
| `--emit-obj --dce` | 529 of 804 | 291416 |
| the same code as an executable | 78 of 805 | 78488 |

6.8x, and it is entirely the root set. Full measurement in
[[feature-a-every-emit-obj-object-links-its-own-full-copy-of-crtl-so-n-objects-cost-n-runtimes]].

## The two answers

**A — self-contained runtime.** An object carries a complete crtl and exports
it weakly. Anything can link against it and get a working `malloc`. This is
what ships today, and `test-emit-obj` block 4b-septies asserts it: two objects
share one heap, one `errno` and one `optind` against a gcc oracle. Cost: every
object is ~335KB of which the user wrote 200 bytes, and 41 busybox TUs are
13.7MB. Per-object DCE cannot help, ever, under this answer.

**B — translation unit.** An object keeps the runtime IT reaches; the rest is
an implementation detail and its symbols go. ~78KB per TU on these numbers, so
busybox lands in single-digit MB before any cross-object work. This is the
semantics option (1) of the parent ticket (a `libcrtl.a`) chooses deliberately
— B is the same change arriving without the archive that makes it deliberate.

## What decides it

**What may a SECOND object assume about the first?** Under A, that any crtl
entry point is there. Under B, only that the object's own declared surface is.
A gcc-compiled TU linking a pxx object is the case that matters: under B it
gets glibc's `malloc` for anything the pxx object did not itself use, and that
is either obviously right or a silent split-runtime bug depending on which
answer we hold.

Note 4b-septies is probably NOT the blocker it looks like: it pins DATA symbols
(one heap, one `errno`, one `optind`) and code DCE does not touch `.bss`. That
is reasoning, not a measurement — check it before quoting it either way.

## Recommendation

**B, gated behind `--dce` only** — so nothing changes for a default object and
the reduction is something a busybox build opts into. It keeps A available and
makes the surface change follow an explicit flag rather than a release. The
mechanism exists and is small: `ParseCProgram` already holds `crtlStart`, the
token index the crtl pull begins at, and nothing carries that onto the
`Procs[]` row.

## Evidence, 2026-09-18 (frankB, Track A): a UND ENTRY IS NOT A LINK REQUIREMENT — A RELOCATION IS

Added here rather than escalated as a new question, because it narrows this
fork's own wording rather than opening another.

Subject: `test/test_emit_obj.pas` for `--target=xtensa` (an ET_REL), with and
without `--dce`, linked against a generated stub shim. DCE now runs on every
displacement target (`95b92d920`), so the option-B reduction is measurable on
this object for the first time.

| | object bytes | PalBackend bodies live | ESP-IDF UND entries | relocations naming them | total relocations |
| --- | --- | --- | --- | --- | --- |
| plain | 381528 | 114 | **20** | 24 | 428 |
| `--dce` | 52476 | 0 | **20** | 0 | 210 |

**The UND count does not move, and that is the finding.** DCE removes CODE; a
symbol-table entry with no surviving reference stays in `.symtab`. So an
instrument reading UND entries reports the object as importing the whole PAL
before and after, and would sit green through the very fix this family wants.

**What decides the link is the relocation.** Both objects were linked against a
shim generated from the `--dce` object's own UND list with every ESP-IDF name
stripped out — so neither `lwip_*`, `vTaskDelay` nor `esp_timer_get_time` is
defined anywhere:

    plain    xtensa-esp32s3-elf-gcc  rc=1   24 `undefined reference` errors
                                            (20 distinct names; the four with
                                            two relocations are reported twice)
    --dce    xtensa-esp32s3-elf-gcc  rc=0   0 errors, a 50500-byte ELF

The `--dce` object still carries all twenty UND entries — the identical list —
and links clean. **`ld` errors on relocation sites, not on undefined symbol
table entries.**

### What this does and does not settle

It is a measurement on the **IMPORT** side. This fork is about the **EXPORT**
side — the 288 weak FUNC definitions — and nothing here touches that.

What it does do is correct a premise in this ticket's own summary. *"the symbol
goes, not just the bytes"* is the semantic change B is priced on, and on the
import side **the symbol does not go and the benefit arrives anyway**: what a
second object may still resolve is unchanged in `.symtab`, while what this
object demands of the linker drops to nothing. If the export side behaves the
same way — weak FUNC entries surviving with their bodies gone — then B's
surface change is smaller than the fork assumes and the recommendation gets
cheaper. **That is a prediction, not a measurement**, and it is the next thing
to measure: build the `60edd4853` C TU both ways and count exported weak FUNC
entries, not bytes. Do not quote it until someone has.

Note also that the 4b-septies reasoning above ("code DCE does not touch
`.bss`") is still unmeasured and this run does not check it — the shared-heap
row was not exercised here.

Measurement recorded in `Makefile`'s `test-emit-obj` ratchet, which moved from
the UND count to the relocation count on the strength of it, keeping the UND
count as a printed number because the two fail differently.

## Evidence, 2026-09-18 (frankB, Track A): the EXPORT side — 298 of 307 vanish under B, and 20 of them are reached by LOWERING

The section above measured the import side. This is the export side, which is
the side this fork is actually about. **Evidence, not a recommendation.**

Subject: the TU this ticket describes, reconstructed — two exported functions
plus a `static` helper, using `snprintf`/`malloc`/`strlen`, no `main`. Rebuilt
at HEAD, so the body count has moved since 2026-09-02 (845 now, 804 then).

### 1. `--dce` does not move the export surface AT ALL

| | object bytes | defined FUNC | weak FUNC exported | global FUNC exported |
| --- | --- | --- | --- | --- |
| `--emit-obj` | 393928 | 845 | **307** | 2 |
| `--emit-obj --dce` | 302848 | 579 | **307** | 2 |

307 both ways. The pass removes 266 LOCAL bodies and their symbols and touches
no export, which is this ticket's own claim arriving as a measurement rather
than as an argument: **the exports ARE the root set**, so per-object DCE cannot
prune them, ever, under answer A.

So the measurement named at the end of the import section — "count exported
weak FUNC entries both ways" — does not settle anything on its own. It measures
that A is what ships. Simulating B is what was needed.

### 2. Simulating B: 298 of 307 vanish

B was modelled outside the compiler, from the object's own relocations, so it is
an instrument that fails differently from the pass under test. Built with
`--emit-obj --function-sections` (internal calls become relocations naming the
callee's FUNC symbol), the call graph is read off `.rela.text`, and the root set
is varied while the graph is held fixed.

**The positive control is the compiler's own answer.** Rooted the way the
compiler roots it — every export, plus `init_array`/`fini_array` targets, plus
address-taken (`R_X86_64_64`) targets, plus every relocation whose SITE falls
outside all 845 bodies (the entry and runtime stubs; this is the `DceOwnerOf`
= -1 rule) — the model says **576 live** against the compiler's **573**. Three
bodies over, 0.5%, and the residual is not chased: the model is used only for
the delta between two root sets, and it over-keeps in both.

Re-rooted at the TU's own two exports and nothing else:

| root set | live bodies | weak exports surviving |
| --- | --- | --- |
| all exports (= today, answer A) | 576 (compiler: 573) | 307 |
| the TU's own two exports (= answer B) | **78** | **9** |

**78 is the number this ticket already records for "the same code as an
executable" (78 of 805).** The model reproduces it from a different direction
without being aimed at it, which is the strongest thing said for it here.

The nine that survive: `malloc`, `memcpy`, `snprintf`, `strerror`, `strlen`,
`__pxx_set_environ`, `__pxx_va_arg_gp`, `__pxx_va_arg_fp`, `__pxx_va_start_impl`.

### 3. Of the 298 that vanish, 20 are routines no source names

    __pxx_builtin_bswap16/32/64   __pxx_builtin_clz32/64   __pxx_builtin_ctz32/64
    __pxx_builtin_ffs32/64        __pxx_builtin_parity32/64
    __pxx_builtin_popcount32/64   __pxx_run_initializers
    __pxx_va_arg_a64_fp  __pxx_va_arg_agg  __pxx_va_arg_agg_a64
    __pxx_va_arg_cross   __pxx_va_arg_cross32   __pxx_va_start_impl32

These are the hazard named in
[[bug-a-a-frontend-cannot-see-that-a-backend-calls-library-routines-it-never-mentions]]
— a backend lowers an ordinary construct onto them and the source never mentions
them. That ticket's own measurement is that the set is TARGET-DEPENDENT and its
predicate is a hand-maintained union (`PXXWriteDecW` riscv32-only; `PXXMemMove`
aarch64/arm32/riscv32, with xtensa taken from a comment).

**Note the split INSIDE one family**: `__pxx_va_arg_gp`/`_fp`/`_va_start_impl`
survive and `_agg`/`_cross`/`_cross32`/`_a64_fp`/`_va_start_impl32` vanish.
Which members survive is decided by which variadic shapes and which target this
TU happened to lower — not by anything a reader of the source can see.

Demonstrated rather than argued. A second TU (`pxx_sum(int n, ...)`, passing a
struct BY VALUE through a variadic) contains **zero** occurrences of `__pxx_` in
its source and reaches `__pxx_va_arg_agg` by lowering — a name in the vanishing
set above.

### The judgement: case 3, but NARROWER than case 3 as stated

The vanishing set does contain routines reached by lowering rather than by
naming, so **B's contract change is not source-auditable** — no review of a
consumer's source can tell you which runtime entries it will need.

**And yet the pxx-to-pxx pair is not at risk, measured.** Both objects have
**zero undefined symbols of any kind** — `--function-sections` reports
`undefined 0` for every CallFix, and `readelf` agrees — because each object
carries a full copy of everything it reaches. That is this family's parent
complaint (N objects cost N runtimes) and it is also what makes B safe between
pxx objects: nobody asks anybody for anything. Linked together against a gcc
`main`, `tu.o` + `tu2.o` build and run (`8 1 5`); each defines its own weak
`__pxx_va_arg_agg` and ld merges them.

So the silent breakage is confined to a consumer that expects the object to
offer what it did not bring itself:

  * a **non-pxx** object linking a pxx one — this ticket's own named case, "a
    gcc-compiled TU linking a pxx object";
  * the **`libcrtl.a`** direction of the parent ticket, where exactly one object
    is meant to provide the runtime for the rest.

Both are the SELF-CONTAINED-RUNTIME reading, which is answer A. Nothing measured
here breaks under B that is not already A's premise.

**What that leaves for the owner is one question with no implementation noun in
it:** *do we promise that a pxx object can supply the runtime for something
else, or only for itself?* Answer "for itself" and B is safe today and the
fork closes. Answer "for something else" and A stands and per-object DCE stays
off the table until the runtime is shared.

Not recommending either — both are coherent and the choice is about what we are
trying to be, which is the one thing a measurement cannot supply.

### What is NOT measured here, stated so nobody quotes it as if it were

  * **x86-64 only.** i386 was built and could not be modelled: its objects carry
    relocations naming DATA symbols only (internal calls are still baked
    displacements there), so no call graph can be read off them. The
    target-dependence of the lowered set is taken from the ticket cited above,
    which measured it; it is not re-measured here.
  * The `PXX*` Pascal runtime routines are all **LOCAL** in a C object (119 of
    them) and are not exported at all, so they are already B-semantics and are
    not in either count. A Pascal object was not measured.
  * 4b-septies' DATA symbols (one heap, one `errno`, one `optind`) are still
    unmeasured; nothing here exercises the shared-heap row.
