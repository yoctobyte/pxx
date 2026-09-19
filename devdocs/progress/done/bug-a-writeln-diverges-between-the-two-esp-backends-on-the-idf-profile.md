---
slug: bug-a-writeln-diverges-between-the-two-esp-backends-on-the-idf-profile
title: "writeln diverges between the two ESP backends on the IDF profile — xtensa silently drops it, riscv32 emits Linux syscalls"
type: bug
track: A
tags: [S]
prio: 70
status: done
found: 2026-09-18
blocks: [umbrella-an-esp32-image-is-as-small-as-it-can-be]
summary: "RESOLVED 2026-09-19 (frankB). **The divergence was already closed by `b3adef718` and this ticket's headline is false at HEAD** -- reproduced before anything else: xtensa and riscv32 now BOTH ask `TargetPlatform` per the ir_codegen.inc:1374 ruling, and write/writeln is a no-op on both profiles and both backends (all four empty-vs-hello pairs byte-identical; `readelf -sW` shows both IDF objects importing exactly calloc and free, so no POSIX write path leaks). THE NO-OP IS A CHOICE, NOT A GAP: b3adef718 declined to route IDF writeln to esp_rom_printf with evidence -- PalBackendWrite REFUSES stdout/stderr on IDF, the docs name esp_rom_printf as the IDF idiom, and examples/esp32/hello-c3 ships it and printed on a real C3 under Espressif qemu. WHAT WAS STILL WRONG, and what this ticket fixed: the warning was ONE message for TWO profiles and its text was the BARE profile's -- on IDF it said \"there is no console\" and cited docs/targets/esp32.md:70, a bullet three lines under the heading \"Notes for the bare profile\". On IDF there IS a console. **The predicate that decides WHETHER to warn and the predicate that decides WHAT TO SAY are different axes**: TargetPlatform is right for the first (nothing is emitted either way) and wrong for the second, and collapsing them produced a warning true about the behaviour and false about the reason and the remedy. That is the stale-hazard shape rather than an ordinary wrong fact -- a warning exists to STOP a reader, it succeeds, and a reader who stops generates nothing that could reveal it was wrong. The message now splits on EspBareBoot though the behaviour does not, and cites SECTIONS not line numbers (four places in this tree cite esp32.md:70, and a doc line number goes stale without erroring). THE TICKET'S OWN PRESCRIBED POSITIVE CONTROL WAS DELIBERATELY NOT IMPLEMENTED: it says to assert empty and hello are NOT identical \"on any profile that claims to have a console\", which encodes the esp_rom_printf routing the tree rejected -- an assertion written from a PREDICTION pins the prediction. The test-core row asserts the DECIDED behaviour instead. Positive control is the PIN and all three assertion classes were shown to fail INDEPENDENTLY rather than assumed to, because the row halts at its first failure: divergence (pinned riscv32 IDF 258788/4072 vs 258828/4112), silence (pinned warns on neither profile), and wrong IDF text (the pre-fix message contains \"there is no console\" and lacks esp_rom_printf). NOT WIDENED, recorded rather than half-done: EspBareBoot has 56 uses across 14 files, most legitimately about bare; two sites have now been corrected one at a time, and a census of the other 54 is real work and a separate ticket."
owner: frankB
---

# The divergence

    ir_codegen_xtensa.inc:3781    if TargetPlatform = PLATFORM_ESP then   { no-op }
    ir_codegen_riscv32.inc:3569   if EspBareBoot then                     { no-op }

`DerivePlatform` (compiler.pas:243) reads
`if EspBareBoot or (TargetArch = TARGET_XTENSA) then TargetPlatform := PLATFORM_ESP`.
**For riscv32 the two spellings coincide** (bare -> ESP, else POSIX) — which is
exactly why copying one for the other looks safe. **For xtensa they do not**:
xtensa defaults to ESP, so an ordinary `--target=xtensa --platform=esp` IDF
build has `EspBareBoot` FALSE and `TargetPlatform` = PLATFORM_ESP.

# Measured 2026-09-18

| build | empty | hello | verdict |
| --- | --- | --- | --- |
| xtensa `--platform=esp --emit-obj` | `code=208948 data=3368` | `code=208948 data=3368` | **byte-identical — dropped** |
| riscv32 `--platform=esp --emit-obj` | `code=258788 data=4072` | `code=258828 data=4112` | **+40/+40 — emitted** |
| xtensa `--esp-profile=bare` | `code=46436` | `code=46436` | identical (documented) |
| riscv32 `--esp-profile=bare` | `code=57900` | `code=57900` | identical (documented) |

`riscv32-esp-elf-objdump -d` on the riscv32 IDF object: **32 `ecall`s**, against
2 in the bare object. `riscv32-esp-elf-nm -u` lists exactly `calloc` and `free`
— **`write` is not an external**, so the write path is internal and reaches the
kernel by `ecall`. On ESP-IDF that is not a Linux `write`; it traps.

# This axis already has a ruling, and it was applied to one subsystem only

`ir_codegen.inc:1374` settles it in its own words, for the SIGNAL runtime:

> *"BUT `not EspBareBoot` IS NOT THAT AXIS ON XTENSA, and the ruling's step 3 got
> this wrong by copying riscv32's spelling rather than its meaning. ... Gating on
> `not EspBareBoot` there would emit a Linux-syscall signal runtime for ESP-IDF
> and CALL its installer at startup. For riscv32 the two spellings coincide
> (bare -> ESP, else POSIX), which is exactly why copying the spelling looked
> safe. TargetPlatform is the axis; EspBareBoot is one input to it."*

**Nobody checked the WRITE path for the same pair of spellings.** That is
CLAUDE.md's own rule arriving in a second subsystem — *"grep for the OTHER
SPELLING'S HANDLER, not for the feature"* — and here the two spellings are in
two files that no grep for `writeln` brings together, because neither arm
contains the word.

# Which one is wrong

**Both.** The ruling says `TargetPlatform` is the axis, so riscv32's
`EspBareBoot` is the wrong QUESTION and its IDF builds emit a write path that
cannot work. But xtensa, asking the right question, still answers by **silently
discarding a statement the programmer wrote** — on a profile where a console
genuinely exists (IDF's own `esp_rom_printf` is named in
`docs/targets/esp32.md`'s Mode 2 section as an external the IDF link resolves).

So the fix is not "make riscv32 match xtensa". It is:

1. **Ask `TargetPlatform` in both** — one question, per the ruling.
2. **On the IDF profile, route write/writeln to `esp_rom_printf`** (or the PAL
   equivalent), which the IDF link already resolves. That is the arm that
   should exist and does not.
3. **Keep the bare no-op**, which is documented and correct, and now warns
   (`bug-a-uPXX_MANAGED_STRING-on-esp-bare-emits-an-empty-image-and-says-ok`).

# Positive control for whoever takes it

Assert that an empty program and a `writeln` hello-world are **NOT** byte-
identical on any profile that claims to have a console, and **ARE** identical on
`--esp-profile=bare`. Both directions, because the first cut of the warning in
the sibling ticket fired on a program with no console output at all and that
only showed up against the empty-program row.

# Worked 2026-09-19 (frankB) — the divergence was already closed; what was left was the warning TEXT

**REPRODUCED AT HEAD FIRST, and the headline did not survive.** The ticket's
central claim — the two backends disagree on the IDF profile — is **false at
HEAD**, and has been since `b3adef718` (2026-09-18 11:51, another seat) made
`ir_codegen_riscv32.inc` ask `TargetPlatform` per the `ir_codegen.inc:1374`
ruling. Measured here, all four combinations:

| build | empty | hello | verdict |
| --- | --- | --- | --- |
| xtensa `--platform=esp` | `code=209920 data=3344` | identical | no-op |
| xtensa `--esp-profile=bare` | `code=46380 data=640` | identical | no-op |
| riscv32 `--platform=esp` | `code=259040 data=3344` | identical | no-op |
| riscv32 `--esp-profile=bare` | `code=57764 data=640` | identical | no-op |

And no POSIX write path leaks on either: `readelf -sW` reports both IDF objects
importing **exactly `calloc` and `free`**, both bare objects importing nothing.

**The behaviour question was decided, not skipped.** `b3adef718` declined to
route IDF write/writeln to `esp_rom_printf` and gave its evidence: PalBackendWrite
REFUSES stdout/stderr on IDF (one of 112 deliberate refusals), the docs name
`esp_rom_printf` as the IDF idiom, and `examples/esp32/hello-c3` ships that idiom
and was booted under Espressif qemu printing real output. So the no-op is a
choice on both profiles and the silence was the only defect — which that commit
also fixed, with a warning.

## What was actually still wrong: a warning true about the behaviour and false about the reason

The warning was ONE message for TWO profiles, and its text is the BARE
profile's. On IDF it said **"there is no console"** and pointed at
`docs/targets/esp32.md:70` — a bullet sitting three lines under the heading
**"Notes for the bare profile:"**. On the IDF profile there IS a console:
`esp_rom_printf`, resolved by the IDF link, documented in that same file's
**"Mode 2: ESP-IDF component"** section, and exercised by a buildable example
that prints on a real C3.

**The predicate that decides WHETHER to warn and the predicate that decides
WHAT TO SAY are different axes.** `TargetPlatform` is right for the first —
nothing is emitted on either profile, which is why one predicate is honest at
the warn site. It is wrong for the second. Collapsing them is what produced a
warning that is true about behaviour and false about reason and remedy, and
**that is the stale-hazard shape rather than an ordinary wrong fact**: a warning
exists to STOP a reader, it succeeds, and a reader who stops generates nothing
that could reveal it was wrong. So the message now splits on `EspBareBoot` even
though the behaviour does not.

The remedy is cited **by section and not by line number**, deliberately: four
places in this tree cite `esp32.md:70`, and a doc line number is exactly the
citation that goes stale without erroring — it points somewhere.

## The ticket's own prescribed positive control was NOT implemented, on purpose

It says to assert that empty and hello are **NOT** byte-identical "on any
profile that claims to have a console" — i.e. that IDF routes to
`esp_rom_printf`. **The tree decided the other way, with evidence.** Writing
that row would pin a PREDICTION rather than the code, which is CLAUDE.md's own
rule and is how a fixture gets written that is red on arrival for a feature that
is working. The row asserts the DECIDED behaviour instead: identical on both
profiles and both backends, warned exactly once, and the warning naming the
right console for each profile.

**Positive control is the PIN, and all three assertion classes were shown to
fail independently rather than assumed to** — the row halts at its first
failure, so a single red run does not prove the later rows can fire:

1. **divergence** — pinned, riscv32 IDF: `code=258788 data=4072` vs
   `code=258828 data=4112`, so the identity assertion fails.
2. **silence** — pinned: no warning on any profile, so the warning assertion
   fails (this is the one a whole-row run reaches first).
3. **wrong IDF text** — the pre-fix message contains `there is no console` and
   does not contain `esp_rom_printf`, so both IDF text assertions fail.

## Not widened, and why

`EspBareBoot` has 56 uses across 14 compiler files. The defect class is narrow —
a site that means "is this an ESP target at all" but asks `EspBareBoot`, which
diverges only on xtensa — and most uses are legitimately about bare (image
layout, the heap arena, the IRAM org). Two sites have now been corrected one at
a time (the signal runtime at `ir_codegen.inc:1374`, the write path at
`b3adef718`). **A census of the remaining 54 is real work and is not this
ticket**; it is recorded here as the obvious next question rather than half-done.
The cheap instrument for it would be leakage-shaped, not read-shaped: build for
xtensa IDF and look for anything POSIX that only a `not EspBareBoot` arm could
have emitted. The undefined-symbol check above is one such probe and it is clean
for the write path.

## Log
- 2026-09-19 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 75dcbd2c0.
