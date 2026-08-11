---
track: U
prio: 45
type: decision
blocked-by: []
---

# Decide: how does the compiler learn WHICH ESP chip, and what does it derive?

- **Type:** decision (Track U) — naming + architecture, affects every ESP
  codegen decision from here on.
- **Raised:** 2026-08-11, scoping
  [[bug-a-riscv32-and-xtensa-have-no-atomic-codegen]]. That ticket asks for
  atomics on riscv32/xtensa and cannot be answered per-ISA, because the answer
  differs *within* riscv32 — which is what surfaced this.

## The problem: the chip is currently IMPLIED by the ISA

There is no chip axis. `--target=riscv32` means "ESP32-C3" by convention, and
the convention is written down in three unrelated places:

- the validation message says it outright —
  `--esp-profile=bare requires --target=riscv32 (esp32c3) or --target=xtensa (esp32s3)`
  (`compiler/compiler.pas`);
- `ESP_BARE_IRAM_BASE` is the **C3's** SRAM map and `ESP_BARE_IRAM_BASE_XT` is
  the **S3's** — two constants picked by ISA (`compiler/defs.inc`);
- `compiler/rv32enc.inc` is headed "RV32IMC codegen" — the C3's exact ISA, with
  no AMO/LR-SC encoders.

That works while there is one chip per ISA. It breaks the moment a second
riscv32 part appears, and it breaks in three independent ways at once: ISA
extensions, core count, and memory map.

## Today's axes

| axis | flag | values |
| --- | --- | --- |
| ISA / backend | `--target=` | `riscv32`, `xtensa`, `x86_64`, … |
| platform | `--platform=` | `esp` \| `posix` (derived from target, overridable) |
| profile | `--esp-profile=bare` | bare metal vs IDF |
| xtensa ABI | `--xtensa-abi=` | `windowed` \| `call0` |

## What IDF calls things (borrow, do not invent)

`idf.py set-target <x>` and `CONFIG_IDF_TARGET_<X>` use one lowercase token, no
separator: `esp32`, `esp32s2`, `esp32s3`, `esp32c2`, `esp32c3`, `esp32c6`,
`esp32h2`, `esp32p4`. Every ESP developer already types these, and an IDF
wrapper can pass `$IDF_TARGET` through untranslated.

Borrowing verbatim also survives Espressif renaming their own scheme — an
invented short form (`--esp=c3`) assumes the `esp32` prefix is a constant, and
`esp32p4` already shows the prefix is a brand rather than a family descriptor.
A future 64-bit part need not be `esp32*` at all.

## The fork: WHERE does the chip live?

**(A) A separate axis — `--esp-chip=esp32c3`**, alongside platform/profile,
defaulting per ISA to today's assumption.
- keeps `--target` meaning "backend", which is what it means everywhere else
  and what CLAUDE.md's track model assumes;
- but `--esp-chip=esp32c3` says "esp" twice, and the ISA and the chip can then
  be set to contradict each other (`--target=xtensa --esp-chip=esp32c3`), so it
  needs a validation rule that (B) makes structurally impossible.

**(B) SoC targets in the existing namespace — `--target=esp32c6`** (recommended).
- one namespace, no redundancy, reads like `idf.py set-target` and like every
  other toolchain's `-mcpu`;
- the SoC target IMPLIES arch + `platform=esp` + the capability row, so the
  contradiction in (A) cannot be expressed;
- **keeps `--target=riscv32` and `--target=xtensa`** as the generic forms:
  riscv32 is genuinely dual-role today (bare C3 **or** hosted linux under
  qemu-user, which the cross-test infrastructure uses), so the generic ISA
  targets must survive. They keep meaning exactly what they mean now — riscv32
  → C3 caps, xtensa → S3 caps — so no existing command line changes behaviour.

## The half that matters more than the name: a CAPABILITY TABLE

Whichever spelling wins, codegen must consult **capabilities, not chip names**.
One table, and every decision site asks it:

| chip | ISA | cores | atomic primitive |
| --- | --- | --- | --- |
| esp32c3 | RV32IMC | 1 | interrupt mask (no `A`) |
| esp32c2 | RV32IMC | 1 | interrupt mask (no `A`) |
| esp32c6 / esp32h2 | RV32IMAC | 1 | AMO / LR-SC |
| esp32p4 | RV32IMAFC | 2 | AMO / LR-SC |
| esp32s2 | Xtensa LX7 | 1 | `S32C1I` |
| esp32 / esp32s3 | Xtensa LX6/LX7 | 2 | `S32C1I` |

The alternative is `if chip = esp32c3 … else if esp32c6 …` spreading across the
backends, the memory map and the peripheral bases — N mechanisms for one
concept, and far harder to unpick later than to set up now
(`devdocs/dev/normalise-dont-special-case.md`).

Capabilities the table owes its callers on day one: `SocCoreCount`,
`SocHasAtomicISA`, `SocIramBase` / `SocStackTop` (already hardcoded per ISA
today), `SocUartBase` (already assumed identical "on both").

## What it immediately unblocks

Atomics stops being a special case and falls out of the table:

- **has atomic ISA** → emit it (`S32C1I` retry loop on xtensa; AMO / LR-SC on
  riscv-with-`A`);
- **no atomic ISA, 1 core** → interrupt-masked critical section (what ESP-IDF
  does on the C3);
- **no atomic ISA, 2 cores** → refuse honestly — and **no ESP part is in that
  box**, so the table proves that gap cannot be silently wrong.

Note the single-core row is not "atomics unnecessary": FreeRTOS preempts tasks
on one core, so a bare `n := n + 1` still tears. Single-core means the CHEAP
primitive suffices, not that none is needed.

## Recommendation

**(B), borrowing IDF's spelling verbatim, plus the capability table** — with the
generic `riscv32` / `xtensa` targets kept as today's defaults so nothing
existing moves. The table is the part worth insisting on; the flag spelling is
reversible, a chip-name conditional sprayed through five files is not.

## Gate (for whoever implements the decision)

`--target=esp32c3` and `--target=riscv32` producing byte-identical output;
likewise `esp32s3` vs `xtensa`; the capability table consulted (not chip names)
at every site that currently hardcodes a C3/S3 fact; self-host byte-identical.
