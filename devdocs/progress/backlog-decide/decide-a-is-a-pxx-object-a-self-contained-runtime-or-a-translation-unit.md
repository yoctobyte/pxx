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
summary: "A pxx --emit-obj object exports its ENTIRE runtime -- 288 weak FUNC symbols for a two-function C translation unit -- and per-object DCE therefore cannot prune it: measured, an object keeps 529 of 804 bodies where the same code as an executable keeps 78. Pruning it changes the object's LINK SURFACE (the symbol goes, not just the bytes), which is a semantic change one existing test asserts against. The fork: is an object a self-contained runtime that anything may link against, or a translation unit whose runtime is an implementation detail? Both are coherent; they differ on what a second object may assume."
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
