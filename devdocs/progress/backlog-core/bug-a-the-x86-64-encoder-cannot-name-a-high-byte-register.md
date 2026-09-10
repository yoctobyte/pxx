---
slug: bug-a-the-x86-64-encoder-cannot-name-a-high-byte-register
title: "`%ah`/`%ch`/`%dh`/`%bh` are unencodable — byte width forces REX for reg 4..7"
track: A
prio: 40
type: bug
status: open
owner: ""
found-by: frankH
created: 2026-09-10
tags: [asm, encoder, x86-64, inline-asm, sdl2, lekkerzeilen]
blocked-by: []
summary: "At byte width `EncPrefixAndREX` (x64enc.inc:56) FORCES a REX prefix for register numbers 4..7, because in this encoder's vocabulary those are spl/bpl/sil/dil. A REX prefix is also exactly what makes the HIGH-byte forms unencodable, so ah/ch/dh/bh cannot be named at all: `AsmRegNum` has no spelling for them, and emitting one as (reg 4, size 1) assembles quietly to spl -- a wrong REGISTER with no diagnostic. Blocks GNU inline asm's `%h` operand modifier, refused by name as of this ticket, and therefore `SDL_Swap16` and every SDL2 header import: `__asm__(\"xchgb %b0,%h0\": \"=Q\"(x):\"0\"(x))` at SDL_endian.h:166. The Q constraint that ticket blamed is FIXED and was not the only wall."
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
