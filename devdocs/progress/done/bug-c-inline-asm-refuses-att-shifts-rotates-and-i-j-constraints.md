---
track: C
tags: [c, x86-64, inline-asm, dropbear]
prio: 60
type: bug
blocked-by: []
summary: "GNU inline asm refused roll/rorl/rolq/rorq and the AT&T shifts (shl/sal/shr/sar), refused %cl as a shift count under an l/q suffix, and refused the ranged immediate constraints \"I\" (0..31) and \"J\" (0..63). That stopped 406 of 647 dropbear TUs, every libtomcrypt file that includes tomcrypt_macros.h. All three are fixed; the encoder already had the instructions."
status: done
owner: claude
---

# AT&T shifts/rotates and the "I"/"J" constraints in C inline asm

Found building dropbear 2026.94 with pxx
([[feature-c-dropbear-builds-with-pxx]]). libtomcrypt's
`src/headers/tomcrypt_macros.h` defines ROL/ROR/ROL64/ROR64 as
`roll %%cl,%0` with `"c"(i)`, and ROLc/RORc/ROL64c/ROR64c as `roll %2,%0`
with an `"I"` (or `"J"`) immediate. These are used on every x86 GNU compiler
unless LTC_NO_ASM is defined.

Three gaps, each one hidden behind the one before it:

1. `AttBaseIsKnown` (compiler/asmatt.inc) did not list shl/sal/shr/sar/rol/ror,
   so the mnemonic was refused before it reached `AsmDispatch`. AsmDispatch had
   encoded all six since the Intel-syntax path got them.
2. The suffix-vs-register check refused `%cl` under `roll`/`rolq`: "writes roll
   with a 8-bit register". A shift count is %cl whatever the suffix says. Slot 1
   of a shift/rotate (the count, after the AT&T reversal) is now exempt when it
   is cl.
3. `"I"` and `"J"` were unknown constraint classes. They are now read as `"i"`,
   evaluated as a constant expression, and range-checked (0..31 and 0..63) the
   way gcc checks them.

The i386 text sink already assembled rol/ror, so `AttKnows386` lists them as
well.

Test: test/casm_rotate_and_shift.c (test-core). It uses the libtomcrypt
macros verbatim and adds shll/shrl/sarl/shlq. Its values are chosen so that a
rotate cannot pass as a shift and left cannot pass as right, and the expected
output is gcc -O0's.
