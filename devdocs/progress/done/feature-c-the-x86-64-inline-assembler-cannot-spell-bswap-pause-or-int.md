---
slug: feature-c-the-x86-64-inline-assembler-cannot-spell-bswap-pause-or-int
track: C
prio: 60
type: feature
status: done
owner: frankH
created: 2026-09-10
found-by: frankH
tags: [cfront, inline-asm, x86-64, sdl, lekkerzeilen, encoder]
blocked-by: []
resolution: PENDING-COMMIT
summary: "bswapl/bswapq, pause and `int $3` were absent from the AT&T reader and the x86-64 encoder, and they are the last of SDL2's inline asm. Censused rather than walked: grepping __asm__ across every /usr/include/SDL2 header names twelve mnemonics, nine of them behind architecture guards this target never takes (rlwimi ppc, dmb/mcr/bkpt arm and aarch64, ebreak riscv), so the x86-64 surface is xchgb+%h0 -- landed at 642943118 -- plus exactly these four. All four land here, verified against gcc on identical source and against `as` byte-for-byte. `import \"/usr/include/SDL2/SDL.h\"` now clears every asm template and stops instead at MAX_PROC_PARAMS in an MMX intrinsic header, which is a different class and a different ticket."
---

# Why a census and not a walk

CLAUDE.md's rule that a first-failure census ranks by queue position applies to
the compiler's own error reporting just as much as to a corpus probe: attempting
`SDL2/SDL.h` reports ONE unsupported instruction, so clearing it reveals the
next and nothing tells you how many are left. Grepping the headers gives the
whole population in one command, and the population is small and closed:

| mnemonic | reached on x86-64? |
| --- | --- |
| `xchgb` (with `%b0`/`%h0`, `=Q`) | yes — landed `642943118` |
| `bswapl`, `bswapq` | yes — **this ticket** |
| `pause` | yes — **this ticket** |
| `int $3` | yes — **this ticket** |
| `rlwimi`, `or 27,27,27` | no, ppc |
| `dmb`, `mcr`, `bkpt`, `brk` | no, arm / aarch64 |
| `ebreak` | no, riscv |
| `rorw` | already supported |

# What landed

- `x64_bswap_reg(size, reg)` in `x64enc.inc`. The register rides in the OPCODE
  (`0F C8+rd`), not a ModRM byte, so REX.B is the only thing naming a register
  above 7 — and a dropped prefix does not fail to assemble, it swaps a
  DIFFERENT register. Behind the shared `EncPrefixAndREX` funnel for exactly
  the reason the `%h0` fix documents: 58 of its 60 call sites reach it
  directly, and a second prefix decision beside it is the wrong-layer bug.
- 16-bit `bswap` is **refused**. It assembles and Intel documents it as
  UNDEFINED, so the one width a caller might reach for by analogy is the one
  that silently produces a wrong runtime answer. Verified the refusal fires.
- `pause` = `F3 90` in `asmenc.inc`, named separately from `nop` because the
  prefix IS the instruction.
- `int $3` = `CC`, matching what `as` emits.

# Guards, and what each can actually see

- `test/test_x64enc.pas`: four bswap rows against `as`, paired so that each
  pair differs in exactly one bit — reg 0 vs 15 at one width isolates REX.B,
  32 vs 64 at one register isolates REX.W.
- `test/casm_bswap_and_pause.c`: values against gcc on identical source.
- The **pause prefix** is a paired byte delta in the Makefile (`F3 90`, 0 -> 1),
  because the value rows cannot see it: a bare nop is a legal implementation of
  pause and the loop still counts to 7.
- `test/casm_int3_traps.c`: the assertion is the SIGTRAP, and the row's sense
  is inverted — a clean exit is the failure.

# Three instruments that lied, all correct about something else

1. **`objdump -d` parses ZERO instructions out of a pxx binary.** It reported
   "no bswap present" for a binary containing three, which reads exactly like
   the feature being absent.
2. **A CC byte count said `int $3` emitted nothing.** With- and without-asm
   binaries came out at identical size with identical CC counts — CC is the
   padding filler — while one traps and the other exits clean.
3. **The pause guard, written to demonstrate framing, was itself unframed.**
   `od | tr -d ' \n'` runs the hex together, so `f390` matched ACROSS two
   adjacent bytes and the CONTROL binary answered 2 where the truth is 0.

# The i386 sibling is NOT covered, deliberately and loudly

`AttKnows386` does not list these and `asmtext_386.inc` cannot assemble them,
so the i386 arm fails with `unsupported instruction` rather than emitting
nothing. That is checked, not assumed: `AttEncodeOne` errors on a False from
`AttEmitInstr`. SDL's i386 arm wants `bswapl` too, so this is a real gap —
named here rather than left for someone to discover, which is the lesson the
`%h0` fix paid for.
