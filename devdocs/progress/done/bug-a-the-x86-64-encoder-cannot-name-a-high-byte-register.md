---
slug: bug-a-the-x86-64-encoder-cannot-name-a-high-byte-register
title: "`%ah`/`%ch`/`%dh`/`%bh` are unencodable — byte width forces REX for reg 4..7"
track: A
prio: 40
type: bug
status: done
owner: "frankH"
found-by: frankH
created: 2026-09-10
tags: [asm, encoder, x86-64, inline-asm, sdl2, lekkerzeilen]
blocked-by: []
summary: "DONE. `%ah`/`%ch`/`%dh`/`%bh` encode now: an opt-in AsmHigh8Operand flag, set only by the AT&T template parser and cleared per instruction, suppresses the byte-width REX force and refuses the combinations the ISA cannot spell (a register >= 8, or 64-bit width). `%h<n>` is implemented in asmatt.inc and refuses an operand whose base is outside a/b/c/d, which is what the `Q` constraint class exists to guarantee. THE GUARD WENT IN AT THE WRONG LAYER FIRST and that is the entry worth reading: placed in AsmPrefixAndREX it covered the AT&T parser's own path, and `movb $0x7F,%h0` reached x64_mov_reg_imm, which calls EncPrefixAndREX directly as 58 of its 60 call sites do. Emitted `40 b5 7f` -- `mov $0x7f,%bpl`, the low byte of the FRAME POINTER -- and segfaulted, while the two rows using other opcodes passed. Moved to EncPrefixAndREX and EncPrefixAndREXMem, the one funnel. Unblocks SDL_endian.h:166 verbatim; SDL2 itself now stops earlier, at the derived soname."
---

# The gap

`EncPrefixAndREX(size, regField, rmReg, force)` emits REX when

```pascal
(size = 1) and (((regField >= 4) and (regField <= 7)) or ((rmReg >= 4) and (rmReg <= 7)))
```

which is correct for `spl/bpl/sil/dil` — those forms exist only with REX. It is
also unconditional, and `ah/ch/dh/bh` are the same four numbers with REX
*absent*. One numbering, two disjoint register sets, and the encoder can only
express the REX one.

`AsmRegNum` has no `ah` spelling either, so nothing upstream can ask for it.
`asmdisasm_x64.inc:110` knows the names for DISASSEMBLY (`'al','cl','dl','bl',
'ah','ch','dh','bh'`) — the reader is complete and the writer is not.

# Why it matters now

`%h<n>` is a GNU inline-asm operand modifier meaning "the high byte of operand
n". Measured across every header on this box: `%w1` 12, `%b0` 6, `%w0` 5,
`%h0` 4. `%b` and `%w` are implemented; `%h` is refused by name because the
silent alternative is worse — `(reg 4, size 1)` assembles to `spl`, which is a
wrong value in a register the caller owns, with nothing printed.

The four `%h0` uses are `SDL_Swap16` in `SDL/SDL_endian.h` and
`SDL2/SDL_endian.h`, and they are on the critical path of the priority target:
`import "/usr/include/SDL2/SDL.h"` cannot complete without them.

# What a fix needs

A way to say "this operand is a high-byte register", carried far enough down to
suppress REX rather than force it. Sketch, not a design:

- a parallel `AsmOpHigh8` flag beside `AsmOpKind`/`AsmOpReg`/`AsmOpSize`,
  defaulting False so nothing that does not set it can change behaviour;
- `EncPrefixAndREX` must then be able to be told **not** to emit REX, which its
  current `force: Boolean` cannot express — it has a force-on and no force-off;
- a refusal when a high-byte operand shares an instruction with anything that
  independently requires REX (a register >= 8, or 64-bit width). That
  combination is illegal in the ISA, not merely unsupported, so it must be
  diagnosed rather than encoded.

**The positive control is cheap and must exist**: assemble `xchgb %ah,%al` and
disassemble it. `86 e0` is the correct encoding; anything with a `40`-`4f`
prefix byte is the bug this ticket describes, and the existing disassembler
already prints the right names to check against.

# Scope note

This is the encoder, which is Track A's, reached from a Track C ticket. It is
filed rather than fixed because "wrong register, no diagnostic" is the class
this project treats as most expensive, and because the change touches the REX
path every backend shares — not because it is large.


## Resolved 2026-09-10, frankH

### The shape

`AsmHigh8Operand` (defs.inc) is set only by `asmatt.inc`'s `%h<n>` arm and
cleared at the head of every instruction's operand loop, so no codegen path can
reach it and it cannot colour the next instruction. `EncPrefixAndREX` and
`EncPrefixAndREXMem` consult it, suppress the prefix, and call `EncHigh8Check`,
which refuses the combinations that are illegal rather than merely unsupported:
a register >= 8 or 64-bit width, either of which needs the prefix that makes a
high-byte name unspellable.

The numbering falls out for free — `ah`=4, `ch`=5, `dh`=6, `bh`=7 is the same
order the disassembler already prints, so the high form of base register r is
`r + 4`, and `EncModRMReg` needs no change at all.

### THE LAYER WAS WRONG FIRST, AND THAT IS THE FINDING

I put the suppression in `AsmPrefixAndREX`, reasoning explicitly that leaving
the shared `EncPrefixAndREX` untouched was the safer choice. **That reasoning
produced the bug.** `AsmPrefixAndREX` is the layer the AT&T template parser's
own encoder uses; `x64_mov_reg_imm` calls `EncPrefixAndREX` directly, and so do
57 other sites. `movb $0x7F,%h0` went straight past the guard.

What it emitted: `40 b5 7f`. That is `mov $0x7f,%bpl` — the low byte of the
frame pointer. **The program segfaulted rather than printing a wrong number**,
which is the one mercy in this failure class and is the reason it was found in
minutes instead of never.

Two of the four test rows PASSED while this was broken. `swap16` and
`highbyte` use `xchgb`/`movb reg,reg`, which do route through
`AsmPrefixAndREX`; only `sethigh`, with an IMMEDIATE, took the other opcode
path. **One arm of a family fixed and one not, with the difference invisible
from the arm that worked** — `devdocs/dev/normalise-dont-special-case.md`, and
the specific instruction it gives (*"fixed one arm of a double case? grep for
the sibling before closing"*) is the step that was skipped. The sibling here
was not a spelling, it was a CALL SITE, and `grep -c 'EncPrefixAndREX('`
answers 60 in one command.

### Controls

| control | result |
| --- | --- |
| four value rows against gcc on identical source | match: 13330 / 171 / 32564 / 2048 |
| the previous compiler | refuses `%h` by name — the file cannot compile |
| byte delta, REX+B0..B7 class, vs the same program with the asm stripped | 4 -> 4, **delta 0** |

The value rows are the framed instrument and they cannot fail quietly: every
register a wrong REX selects (spl/bpl/sil/dil) is the low byte of rsp, rbp, rsi
or rdi. A wider byte scan was tried and is **not** reported as evidence — over
a whole binary, `40..4f` followed by a byte opcode has no instruction framing
and sits near 846 either way, so it cannot resolve two instructions. It is
quoted only for the B0..B7 class, where the baseline is 4 and the delta means
something.

### What this does and does not unblock

`SDL_endian.h:166` compiles and runs, verbatim, matching gcc. `import
"/usr/include/SDL2/SDL.h"` still does not: it now stops EARLIER, at
`memcmp` being imported from the derived soname `libsdl.so`, which is
[[feature-n-derive-a-header-s-library-from-its-directory-and-verify-it-against-the-library-s-own-dynsym]]
and is the next thing in this chain.

Test: `test/casm_high_byte_register.c`.
