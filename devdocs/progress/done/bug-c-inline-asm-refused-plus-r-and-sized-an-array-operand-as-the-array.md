---
track: C
tags: [c, x86-64, inline-asm, dropbear]
prio: 50
type: bug
blocked-by: []
summary: "Two inline-asm operand gaps from dropbear. \"+r\" (read-write) was refused by name; it is now an output plus a hidden input tied to it, numbered after every explicit operand as gcc does. An array passed to an \"r\" input (libtomcrypt's STORE32H, \"r\"(seqbuf)) was sized as the array and got a 32-bit register; it now decays to its address."
status: done
owner: claude
---

# "+r" operands, and an array as an "r" input

Found building dropbear 2026.94 ([[feature-c-dropbear-builds-with-pxx]]).

**"+r".** sntrup761.c's constant-time helpers are written
`__asm__ ("sarw $15,%0" : "+r"(x) : : "cc")`. CAsmRefuseUnsupported refused
every "+" operand and suggested rewriting it as "=r" plus a tied input. That
is a source change, and the dropbear rules forbid one. pxx now makes that
rewrite itself after the operand sections are parsed. Each "+" output gets
an input with a matching constraint (its own number) and a clone of the
lvalue. These hidden inputs are appended after every explicit operand, so
`%N` in the template still means what the programmer wrote (gcc numbers them
the same way). Details:

- The lvalue is evaluated twice, once to load and once to store. An lvalue
  with side effects (`"+r"(*p++)`) is refused by name rather than run twice.
- "+&r" is accepted as "+r": every operand has a register of its own here, so
  the earlyclobber promise holds by construction.
- "+m" stays refused. A memory output has no carrier in this frontend. Gibux
  asked about it and is fine with that.

**Array operand.** libtomcrypt's x86-64 STORE32H/STORE64H are
`"movl %0,(%1)" :: "r"(x), "r"(y)` with `y` an `unsigned char[4]` (packet.c,
chachapoly.c). The operand width came from the array's type, so it got a
32-bit register and `(%1)` was refused ("needs a 64-bit base register").
Copying it would have carried the bytes instead of the address. A non-"m"
input whose expression is an array now decays to `&arr`, as it does in any
other rvalue.

Test: test/casm_plus_r_and_array_operand.c (expected values are gcc -O0's).
It has the sntrup761 helpers verbatim, a "+r" beside an explicit input the
template names by number, "+r" on a struct member, and STORE32H/STORE64H with
the stored bytes printed.
