---
track: A+S
prio: 55
type: bug
status: done
found: 2026-08-30
found-by: claude-A
---

# riscv32 passes stack arguments in REVERSE psABI order, so pxx↔C interop is wrong at ten or more words

pxx places overflow argument word *k* at `[entry_sp + (pnWords-1-k)*4]` —
**descending**. The RISC-V psABI places the first overflow word at `sp+0` and
counts **up**. Pascal↔Pascal and C-mode↔C-mode are unaffected because both ends
of a pxx call share the mistake; every call that crosses to a real C toolchain
is wrong.

Filed separately from the cdecl campaign at the coordinator's direction: the
consumer here is **Track S**, not Pascal-bodied `cdecl` procs, and folding it
into a ticket about `cdecl` is where S would never look for it.

## Measured, against a real oracle

`riscv32-esp-elf-gcc` 15.2.0, `-march=rv32imc_zicsr_zifencei -mabi=ilp32`,
installed under `~/.espressif/tools/riscv32-esp-elf/esp-15.2.0_20251204`. Ten
`int` parameters, read from **both** sides so the reading is not one
interpretation twice:

| ten int params | word 8 (`i`) | word 9 (`j`) |
| --- | --- | --- |
| gcc caller places | `0(sp)` | `4(sp)` |
| gcc callee reads (`-O1`) | `0(sp)` | `4(sp)` |
| **pxx callee reads** | **`20(s0)` = entry_sp+4** | **`16(s0)` = entry_sp+0** |

## What is disassembled and what is read from source

The **callee** half is disassembled, from both compilers. The **caller** half is
not disassembled: it is read from the source, `ir_codegen_riscv32.inc:2756`,
whose own comment states the layout — *"word k is pushed in index order so it
lands at `[sp + (nWords-1-k)*4]`"*. It was originally *derived* (the callee
provably reads word 8 from entry_sp+4, and pxx↔pxx returns the right answer, so
the caller must write it there); the source read replaced the inference. Both
agree, and they are not the same evidence.

## NINE WORDS PROVES NOTHING — use ten

At exactly nine words there is a single overflow word and `(9-1-8)*4 = 0`, so
the descending formula and the ascending psABI **coincide**. A nine-argument
probe returns a clean green. That probe was written first here and it passed.
The split-double corner (seven ints then a `Double`: low half in `a7`, high half
at entry_sp+0) is nine words as well, so the second natural probe is blind for
the same arithmetic reason.

Anyone re-verifying this must use **ten or more words**, or they will reproduce
the first probe, get a pass, and conclude it is fixed.

## Three implementers, and they must move together

| # | file | side | sites |
| --- | --- | --- | --- |
| 1 | `ir_codegen.inc` | Pascal callee spill | 1486, 1506, 1513, 1528 |
| 2 | `cparser.inc` | C-mode callee spill | 11250, 11257, 11272 |
| 3 | `ir_codegen_riscv32.inc` | caller | 2756 |

Measured: a C-mode riscv32 program calling a 10-arg function through a pointer
prints `cmode=100 direct=100` today — correct, because (2) and (3) agree. Flip
(1) and (3) without (2) and every C-mode riscv32 program with ≥10 words breaks.
**A partial fix is strictly worse than the current state**, which is at least
uniformly wrong.

## The consumer is real

`--emit-obj` exists for `--target=riscv32|xtensa` precisely so ESP-IDF C can
call pxx-emitted code — `examples/esp32/timer-c3` is that path. This is not an
observable no compiling program can reach, so it is not a `rejected/` ticket
under the CLAUDE.md table.

## Falsifier, already run and clean

Nothing depends on the descending layout in a way a coordinated change cannot
fix: no hand-written riscv32 assembly anywhere in `lib/` (no `.s`/`.S` files at
all), and no frozen test expectation encoding riscv32 stack offsets.

## Related

`bug-a-arm32-cdecl-has-no-aapcs-stack-argument-area` — arm32 uses the same
descending layout (`[fp + 8 + (pnWords-1-k)*4]`) and AAPCS32 also specifies
ascending stack arguments, so arm32 likely has this defect too. It is currently
unreachable through `cdecl` because arm32 refuses any argument block over 4
core registers. **Not measured against an arm32 oracle** — flagged so it is not
found later as a surprise.

xtensa is **not measured** and is not assumed to share this shape.

## Log
- 2026-08-30 — resolved, commit 50ee2f8a7.
