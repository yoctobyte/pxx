---
track: B
tags: [asm, x86-64, elf, gibux]
prio: 50
type: feature
blocked-by: []
summary: "The GNU as frontend now takes .code16, so Gibux's SMP AP trampoline (real mode, then .code32, then .code64, in one file) assembles with pxx. 16-bit code is encoded through the .code32 path and then rewritten. The operand size flips (66 dropped for 16-bit operations and added for 32-bit ones, never for mov to CR/DR/sreg). An absolute address becomes ModRM rm=110 + disp16 (R_X86_64_16), with moffs A0-A3 for the accumulator. A 32-bit register in an address gets 67. inc/dec and 81/C1-by-1 take gas's short forms. Branches are rel16, ljmp/lcall/ret/iret/lret pick 66 by suffix, and loopl/jecxz take 67. The .code16 region of test/gas_frontend_code16.s is byte-identical to gas's."
status: done
owner: unassigned
---

# The GNU as frontend assembles .code16

Asked by the Gibux session on 2026-11-13. Its SMP kernel compiled with pxx
except `arch/x86_64/trampoline.S:30: .code16 is not supported`. The file is
the AP start-up trampoline: it runs in real mode, does `lgdtl`, sets CR0.PE,
does `ljmpl $8, $abs` into `.code32`, loads CR4/CR3/EFER/CR0, and does
`ljmp $24, $abs` into `.code64`. It addresses everything as
`TRAMP + (label - start)`, a difference of two labels in the section, which
folds to a constant.

## How

No second encoder. Under `.code16`, `GasCode32` is set as well, so every
instruction is encoded the `.code32` way, and REX and rip are refused as
before. `GasCode16Fix` (compiler/gasfront.inc) then rewrites the bytes:

- **Operand size.** `GasOpSize16` takes the operand size from the suffix
  or from the widest general register named. A 16-bit operation loses its
  0x66 and a 32-bit one gains it. The exceptions are 0F 20-23 (mov to and
  from CR/DR) and 8E (mov to a segment register), which have no operand
  size. gas does the same.
- **Address size.** Every absolute memory operand goes through a
  placeholder under `.code16`, constant ones included, so its SIB disp32
  (ModRM 00 reg 100, SIB 25) can be found and turned into ModRM 00 reg 110
  + disp16. That is a 2-byte GFK_ABS fixup: R_X86_64_16, or a constant that
  must fit 16 bits. A mov between al/ax/eax and an absolute address takes
  gas's moffs form A0-A3. A 32-bit register in the address keeps the 32-bit
  form and gets 0x67. The 16-bit forms ((%bx), (%bp,%si), ...) are refused
  by name, because the encoder has no 16-bit ModRM.
- **Prefix order** is gas's: 67, then 66, then the opcode.
- **Short forms gas picks.** `inc`/`dec` of a register become 40+r/48+r;
  `81 /r` with an immediate that fits a signed byte becomes `83 /r ib`; a
  shift by 1 (`C1 /r 01`) becomes `D1 /r`.

Outside the encoder:

- `jmp`, `call` and `jcc` are E9/E8/0F 8x with rel16 (a 2-byte fixup;
  R_X86_64_PC16 when not local). `calll`/`jmpl` keep rel32 behind 0x66.
- `loopl` and `jecxz` take 0x67, and `jcxz` is plain E3. Outside
  `.code16`, `jcxz` is 67 E3 in `.code32` and refused in 64-bit code, where
  E3 is jrcxz.
- `ljmp`/`lcall $sel, $off`: plain is the mode's default (ptr16:16 under
  `.code16`), `l`/`w` pick a size, and 0x66 is added when that is not the
  default.
- `retl`, `lretl` and `iretl` take 0x66 under `.code16`; the `w` forms take
  it elsewhere.
- `pushfl`, `popfl`, `movsl`, `stosl`, `lodsl`, `cltd`, `cwtl` and `leavel`
  take 0x66 under `.code16`. `movsw`, `stosw`, `lodsw`, `cbtw`, `cwtd`,
  `pushfw` and `popfw` are new, with 0x66 outside `.code16`.

## Test

`tools/check_gas_frontend.sh` (the existing cgas row) now also assembles
`test/gas_frontend_code16.s` with pxx and with GNU as:

- the `.code16` region (up to `t16b`) must be **byte-identical**;
- its relocations must be identical (two R_X86_64_16, one of them through a
  folded label difference);
- the `.code16` branches in `.text.br` must disassemble to the same
  instruction text (gas relaxes them to rel8, pxx keeps rel16);
- `movw (%bx), %ax` must be refused with a message that says why.

## Known differences from gas (unchanged, not .code16)

- `.code32` absolute addresses use the SIB no-base form (7 bytes for a mov
  to eax) where gas uses moffs or ModRM rm=101. Both decode the same. The
  header of gasfront.inc gives the reason, and check 2 normalises it.
- `.balign` in code pads with 0x90 where gas uses multi-byte NOPs.

So Gibux's trampoline is byte-identical to gas's in its 16-bit part. Its
`.code32` part is 8 bytes longer, and the folded `TRAMP + (x - start)`
constants that point past it differ accordingly; inside the object they are
consistent.

## Not done

- 16-bit ModRM addressing ((%bx), (%si), (%bp,%di), ...).
- A symbolic immediate in a 16-bit operation (`movw $sym, %ax`): the
  placeholder needs a 32-bit field, so it is refused, as before.
- `movzb*`/`movzw*`/`movsb*` AT&T spellings are missing from the AT&T
  reader in every mode (it knows `movzx`/`movsx`).
