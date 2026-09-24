---
slug: bug-s-every-esp-test-guards-its-idf-arm-on-a-symbol-the-compiler-never-defines
track: S
tags: [S, M]
type: bug
prio: 0
status: rejected
owner: ""
created: 2026-09-24
found-by: frank (frankb-8e, while writing an ifdef for the bare Str test and checking which symbol was real)
blocked-by: []
summary: "REJECTED BY ITS OWN AUTHOR 2026-09-24, SAME NIGHT, BEFORE ANYONE ACTED ON IT -- THERE IS NO DEFECT HERE AT ALL. The claim was that `PXX_ESP` is never defined so 36 test files guard a dead IDF arm. The first half is true of the COMPILER and irrelevant: all 36 files MINT PXX_ESP THEMSELVES at the top, `{$ifdef CPU_XTENSA}{$define PXX_ESP}{$endif}` plus the CPU_RISCV32 twin, and CPU_XTENSA/CPU_RISCV32 ARE defined per target (verified independently). Re-probed on the REAL files rather than a synthetic one: the in-body arm is TAKEN on xtensa, riscv32 and esp32c3 bare and not on x86-64; the esp_rom_printf IDF-output arm is TAKEN on --emit-obj both with and without --platform=esp, and not on bare, and not on x86-64. Every arm resolves correctly on every profile. The `--emit-obj` half is not a trap either: PXX_ESP_IDF is live and correctly used by builtinheap, lib/rtl/dns.pas and dns_libc.pas, and dns.pas DOCUMENTS the --platform=esp condition and depends on it deliberately. WHY THE TICKET EXISTED, and it is this tree's own population rule with the author standing in the worked example: my probe file DID NOT CONTAIN THE SELF-DEFINE LINES that every real file carries, so it was correct about the compiler's built-in defines and STRUCTURALLY SILENT about the subject -- a population that cannot contain the thing being asked about. The probe technique (a deliberate syntax error inside the guarded arm, so the answer is a compiler diagnostic) is sound and is what resolved this in ten minutes; it was aimed at the wrong file. AND THE INSTRUMENT LESSON I ATTACHED TO IT IS ALSO WITHDRAWN, IN THE OPPOSITE DIRECTION FROM HOW I FILED IT: I reported that `strings -a <object> | grep esp_rom_printf` had INVERTED the answer. It had not -- `strings` was RIGHT both times. esp_rom_printf really is in the --emit-obj object, and renaming the guard to PXX_ESP_IDF really did remove it, because PXX_ESP_IDF needs --platform=esp which that invocation lacks. The artefact grep was correct and my synthetic compile-time probe was the wrong instrument, which is the exact reverse of what I told two peers. KEPT AS A CENSUS CORRECTION FOR ANYONE COUNTING THESE: whole-word is 36 files / 144 occurrences outside builtinheap; my filed 130 came from `grep 'PXX_ESP}'` with no -w, and franks-5b's first pass got 44/161 by substring-matching PXX_ESP_BARE. Three counts, one symbol, two grep hazards -- use -w and say so. NOTHING TO DO. Filed in rejected/ rather than deleted so the reasoning is reachable and so the next seat who notices that PXX_ESP is absent from paslexer.inc finds this instead of re-deriving it."
---

# Every ESP test guards its IDF arm on a symbol the compiler never defines

Measured 2026-09-24 at `0adefbd789`, compiler `af40370a8a91d298`.

## The probe, and it is a compile-time probe for a reason

A deliberate syntax error inside the guarded arm, so the answer is a compiler
diagnostic and not an inference:

```pascal
{$ifdef PXX_ESP}
  this_symbol_is_defined_deliberate_error;
{$endif}
```

| invocation | `PXX_ESP` | `PXX_ESP_BARE` | `PXX_ESP_IDF` |
| --- | --- | --- | --- |
| `--target=esp32c3 --esp-profile=bare` | not defined | **DEFINED** | not defined |
| `--target=esp32c3 --emit-obj` | not defined | not defined | not defined |
| `--target=esp32c3 --emit-obj --platform=esp` | not defined | not defined | **DEFINED** |

**`PXX_ESP` is never defined, on any profile.** The middle row is the second
finding: the Mode 2 invocation in `docs/targets/esp32.md` defines neither symbol.

## Where `PXX_ESP` does exist

`compiler/builtin/builtinheap.pas:18`:

```pascal
{$ifdef PXX_ESP_BARE}{$define PXX_ESP}{$endif}
```

A unit-local define, and its header is explicit that within that unit the name
means **bare** (*"Only a BARE boot (PXX_ESP_BARE) is ESP for this"*) — it was
added to FIX an earlier version that defined it unconditionally on xtensa. So the
name is correct where it lives and means the opposite of what the tests want:
the tests reach for it in the `{$else}` of `PXX_ESP_BARE`, i.e. to mean **IDF**.

Two compiler comments (`pasparser_prog.inc:61`, `:1627`) and one in `dce.inc`
refer to `{$ifndef PXX_ESP}` bodies without saying the symbol is unit-local,
which is how the name reads as ambient.

## The shape in the tests

```pascal
{$ifdef PXX_ESP_BARE}
  ... UART MMIO ...          { live on bare }
{$else}
{$ifdef PXX_ESP}
  ... esp_rom_printf ...     { DEAD -- never compiled, on any profile }
{$else}
  ... Write(Chr(code)) ...   { what an IDF build actually gets }
{$endif}
{$endif}
```

The bare arm is live and correct, which is why the bare rows in `test-esp-bare`
genuinely test the ESP ISAs. The IDF arm has never been compiled.

## An instrument that answered this BACKWARDS

Worth recording, because it is the house failure mode and it nearly landed:
`strings -a <object> | grep esp_rom_printf` answered **YES** for the unmodified
file and **NO** after renaming the guard to `PXX_ESP_IDF` — the exact opposite of
the truth, which would have been written up as "the arm is live and the rename
breaks it". `strings` answers about byte sequences anywhere in a file, which is a
different question from "was this arm compiled". It was caught only because the
compile-time probe contradicted it sixty seconds later. **Ask the compiler which
arm it took; do not ask the output what words it contains.**

## Why this is not the one-line rename it looks like

- Flipping 130 guards to `PXX_ESP_IDF` **enables** 130 arms that call IDF
  externals. The Makefile's own IDF rows say they need a full ESP-IDF checkout
  and are therefore not in `make test`, so nothing in this tree can verify the
  arms that would light up.
- Defining `PXX_ESP` compiler-wide for both profiles would make the tests mean
  what they intended — and **collides with builtinheap's local use of the same
  name for bare only**, which exists because an earlier unconditional define was
  a bug. Renaming builtinheap's local symbol is the cleaner half of that.
- So the first move is to settle which name means "an ESP target of either
  profile", then change the tests to it. That is an engineering decision and
  wants measuring, not escalating.

## Controls for whoever takes it

1. **A row that proves an arm COMPILED, not that a test passed.** Every affected
   test is green today; greenness is what hid this. Assert the symbol reference
   (`esp_rom_printf` in the object's symbol table) or assert a deliberate error
   inside the arm, as the probe above does.
2. **The bare arm must not move.** `PXX_ESP_BARE` is correct and live; a
   whole-file rename that touches it would break the rows that work.
3. **builtinheap must keep meaning bare.** Its unconditional-define bug is
   already in its header as a fixed defect; re-introducing it is the regression
   this ticket could most easily cause.

# Umbrella

[[meta-a-pxx-produces-linkable-code]]

## 2026-09-24 (frank, frankb-8e) — REJECTED, and the measurements that reject it

franks-5b re-ran my own probe on the real files and got the opposite answer
within minutes of the filing. I reproduced it independently before accepting it.

### The probe, aimed at the RIGHT population this time

A deliberate error injected into the real file's first in-body arm
(`test/test_esp_dynarray.pas`), and into `test/test_esp_bare_float.pas`'s
`esp_rom_printf` arm:

| invocation | in-body arm | `esp_rom_printf` arm |
| --- | --- | --- |
| `--target=xtensa --esp-profile=bare` | **TAKEN** | not taken (MMIO arm wins, correctly) |
| `--target=riscv32 --esp-profile=bare` | **TAKEN** | — |
| `--target=esp32c3 --esp-profile=bare` | **TAKEN** | not taken |
| `--target=esp32c3 --emit-obj` | — | **TAKEN** |
| `--target=esp32c3 --emit-obj --platform=esp` | — | **TAKEN** |
| x86-64 | not taken | not taken |

**Every arm resolves correctly on every profile.** All 36 files carry
`{$ifdef CPU_XTENSA}{$define PXX_ESP}{$endif}` and the `CPU_RISCV32` twin at the
top — 36 of 36, checked — and both CPU symbols are defined per target, verified
with the same probe.

### The error, which is this file's own population rule

My probe was a synthetic five-line program. **It did not contain the self-define
lines that every real file carries**, so it was correct about the compiler's
built-in defines and structurally silent about the question I was asking. A
population that cannot contain the subject returns a clean, confident, wrong
answer — and I had spent the evening writing that sentence about other people's
measurements.

It is also the second time in one night I made the same shape of error: the stale
binary was the right instrument aimed at the wrong subject too. 5b's phrasing is
the one to keep — *"the right instrument, the wrong subject"* — and the thing that
caught both was somebody re-measuring rather than re-reading.

### The instrument lesson is withdrawn IN THE OPPOSITE DIRECTION

I told two peers that `strings -a <object> | grep esp_rom_printf` had **inverted**
the answer, and offered "ask the compiler which arm it took; do not ask the output
what words it contains" as the generalisable form.

**`strings` was right both times.** `esp_rom_printf` genuinely is in the
`--emit-obj` object, because that arm is genuinely taken. And it genuinely
disappeared when I renamed the guard to `PXX_ESP_IDF`, because `PXX_ESP_IDF`
requires `--platform=esp` and that invocation lacks it — so the rename really did
break it. The artefact grep was the reliable instrument and my synthetic
compile-time probe was the unreliable one, which is the exact reverse of what I
reported.

**What survives is narrower and worth less than what I claimed:** a deliberate
error inside a guarded arm is a good way to ask which arm compiled, *provided the
file you run it on is the file in question*. It is not a reason to distrust a
grep of the artefact. Both peers have been told; 5b was about to bank the wrong
version in the playbook.

### Census correction, since three counts now exist for one symbol

| count | how | what it actually measured |
| --- | --- | --- |
| 130 occurrences | mine, `grep 'PXX_ESP}'` | no `-w`; missed occurrences not followed by `}` |
| 44 files / 161 | 5b's first pass | substring-matched `PXX_ESP_BARE`, a different symbol |
| **36 files / 144** | `grep -rnw`, minus builtinheap | the real figure |

Two grep hazards, one symbol, two seats, inside an hour. Use `-w` and say that
you did.
