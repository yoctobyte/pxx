---
slug: bug-s-every-esp-test-guards-its-idf-arm-on-a-symbol-the-compiler-never-defines
track: S
tags: [S, M]
type: bug
prio: 40
status: open
owner: ""
created: 2026-09-24
found-by: frank (frankb-8e, while writing an ifdef for the bare Str test and checking which symbol was real)
blocked-by: []
summary: "MECHANISM: `PXX_ESP` is NOT a compiler define on any profile. The compiler defines exactly two ESP symbols, both in paslexer.inc -- `PXX_ESP_BARE` (:1217, under EspBareBoot) and `PXX_ESP_IDF` (:1032, under platform=esp and a non-bare ESP ISA). `PXX_ESP` exists only as a LOCAL define inside one unit: builtinheap.pas:18 does `{$ifdef PXX_ESP_BARE}{$define PXX_ESP}{$endif}` for its own bodies, where it deliberately means BARE. Every `{$ifdef PXX_ESP}` in program source is therefore a guard that can never fire. POPULATION, stated so a re-run can tell a regression from a different denominator: 36 files, 130 occurrences, measured at 0adefbd789 by `grep -rn 'PXX_ESP}' --include=*.pas` minus builtinheap -- and ALL 36 ARE UNDER test/, so the blast radius is test coverage and not shipped behaviour. No unit under lib/ or examples/ is affected. WHY IT IS GREEN AND STILL WRONG: in the ESP tests the dead arm is the IDF OUTPUT path, so on an IDF build the three-way ifdef falls through to the HOSTED arm, which uses `Write` -- and writeln DOES work on IDF, so every row passes. The cost is that NO ESP TEST EVER COMPILES ITS esp_rom_printf PATH, in the profile the owner ruled on 2026-09-23 is the ASSUMED one, and the `{$ifdef PXX_ESP} while True do ;` tails never compile either, so bare programs rely on the fall-off-end self-loop instead of the idiom docs/targets/esp32.md tells users to write. A SECOND TRAP MEASURED BESIDE IT, and it is in the docs' own invocation: `PXX_ESP_IDF` needs `--platform=esp`, so `--target=esp32c3 --emit-obj` -- the Mode 2 command docs/targets/esp32.md shows -- defines NEITHER ESP symbol, and a source following the documented pattern silently takes its hosted arm. NOT FIXED HERE because the fix is not the rename it looks like: flipping 130 guards to `PXX_ESP_IDF` ENABLES 130 arms that call into IDF externals (esp_rom_printf, vTaskDelay), which cannot be verified without a full ESP-IDF checkout -- the Makefile says so itself about the IDF rows -- and the alternative, defining `PXX_ESP` compiler-wide for both profiles, collides with builtinheap's local use of the same name for BARE ONLY. That collision is the thing to decide first and it is an engineering call, not an owner one. WHAT WOULD RETIRE IT: one ESP test whose IDF arm demonstrably COMPILES (a symbol-table assertion that esp_rom_printf is referenced, since a passing row proves nothing here), plus a guard that refuses a NEW `{$ifdef PXX_ESP}` outside builtinheap, plus the docs' Mode 2 command either gaining `--platform=esp` or the define gaining an `--emit-obj` arm."
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
