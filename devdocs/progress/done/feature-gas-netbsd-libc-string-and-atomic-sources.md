---
track: C
tags: [gas, assembler, inline-asm, x86-64, rump, netbsd]
prio: 20
type: feature
blocked-by: []
summary: "All 18 x86-64 .S sources of NetBSD's rump build (libc string routines, atomics, byte swaps, ffs, libkern random/scanc/skpc) assemble with pxx's GNU as frontend, and the routines agree with glibc on 20,000 random cases each. Added: test with an immediate, imul's 1- and 3-operand forms, movz/movs with both widths in the mnemonic, %ah/%ch/%dh/%bh by name, shld/shrd, movabs in inline asm."
status: done
owner: claude-dupwt
---

# NetBSD's x86-64 libc/libkern assembly sources

The rump measurement harness (nilix docs/rump-pxx/harness/pxxcc.py) marked
every `.S` as "pxx has no GNU-as front end" without trying it. pxx has one
(gasfront.inc, written for Gibux's boot.S). Run for real at fd6e101d43, 8 of
the 18 files assembled. The other 10 hit encoder gaps in the shared AT&T
reader (asmatt.inc) and encoder (asmenc.inc), so C inline asm had the same
gaps:

| gap | file | added |
|---|---|---|
| `testb $7,%dil`, `test $imm, mem` | strlen, memset, strchr, ... | F6/F7 /0 and the A8/A9 accumulator form; a register in either slot |
| `imul $0x80,%r8,%r9`, `imul $5,%rax` | memset | 6B ib / 69 id |
| `imull randseed(%rip)` | random | F6/F7 /5 |
| `movzbq %sil,%rcx`, `movzwl`, `movsbq`, `movslq` | strchr, strrchr, strcmp | AttMovxSpelling → movzx/movsx/movsxd |
| `xchgb %ah,%al`, `movb %cl,%ch` | byte_swap_2, strcmp | %ah..%bh by name, through the existing %h-operand path |
| `shld $1,%eax,%edx` | random | 0F A4/AC ib, 0F A5/AD (cl) |

Fixing these exposed a silent miscompile in the frontend:
[[bug-gas-a-64-bit-immediate-was-truncated-to-32-bits]].

C inline asm also gains `movabs`/`movabsq $imm64, %reg` (gasfront already had it).

## Proof

- `test/gas_frontend_x64_encodings.s`: 56 instructions, byte-identical to GNU as
  (tools/check_gas_frontend.sh check 5).
- `test/c_inline_asm_att_widths.c`: the same shapes through inline asm, against
  gcc at -O0 and -O2.
- Out of tree: the 18 objects, symbols prefixed `nb_`, linked into a gcc
  harness. strlen, strchr, strrchr, strcmp, strcpy, strcat, memchr, memcpy,
  memmove, memset, ffs, bswap16/32/64, scanc, skpc, the atomics and random()
  agree with glibc / C references on 20,000 random cases each. The same
  harness on gas-assembled objects also passes, and pxx's memset failed it
  until the immediate fix.

## Known encoding differences (valid, not byte-identical)

`xchgb %ah,%al` puts the registers in the other ModRM fields, `shrb $1` uses
C0 ib 1 where gas uses D0, and a byte ALU immediate on `%dl` gets a redundant
REX (the /ext digit 4..7 is read as a byte register by the REX rule). All
three are the same instruction semantically.
