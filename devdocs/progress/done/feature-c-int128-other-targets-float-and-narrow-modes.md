---
track: C
tags: [c, int128, attributes]
prio: 40
type: feature
blocked-by: []
summary: "Done 2026-11-23. __int128 on x86-64 and aarch64 (gcc has it on no other pxx target; the 32-bit ones refuse it in gcc's words). int128<->float both ways, correctly rounded. SysV/AAPCS64 16-byte alignment for __int128 and for structs aligned to 16, checked against gcc (x86-64, linked) and clang (aarch64, call sites). (__int128)x casts. mode(QI/HI/SI/DI) on variables and members. Follow-up: bug-c-aarch64-returns-a-small-struct-through-x8-where-aapcs64-uses-x0-x1."
status: done
owner: unassigned
---

# __int128 beyond x86-64, and the narrow attribute modes

Follow-up to [[feature-c-int128-and-attribute-mode]] (x86-64, 2026-11-18).

- **Other targets.** Each one refuses `__int128` by name. aarch64 is the
  natural next target: x0:x1 pairs, with `umulh` for the high half of a product.
  i386 and the 32-bit targets would need four-word values.
- **Float conversion.** Both directions are refused. This needs a correctly
  rounded conversion in pxx's own RTL (no libgcc). No corpus program has hit
  it yet.
- **Stack-passed alignment.** SysV aligns an `__int128` passed in memory to 16
  bytes. pxx passes it as two adjacent 8-byte slots without padding, which is
  only wrong when a call has run out of registers AND the callee was compiled
  by gcc.
- **mode(QI/HI/SI/DI).** Still skipped, so the typedef keeps its base type;
  `int x __attribute__((mode(QI)))` stays 4 bytes. No corpus program has hit
  it yet.

## mode(QI/HI/SI/DI) on variables and members done 2026-11-23 (claude-pxx)

The typedef path had them since bug-c-attribute-mode-qi-hi-si-di-was-ignored;
a variable or struct member did not (`int x __attribute__((mode(QI)))` was 4
bytes, gcc 1, and held 300 where gcc holds 44). Locals, globals and members
now apply it (CModeForDeclarators), scoped as gcc scopes it: among the
specifiers it covers every declarator, after a declarator only that one.
pxx gives sibling declarators one base type, so the second case in a
declaration with several declarators is refused by name. Test
c_attribute_mode_on_variables (same as gcc on six targets),
c_attribute_mode_one_of_several_refused.

## Stack-passed __int128 alignment done 2026-11-23 (claude-pxx)

SysV puts an __int128 in memory at a 16-byte aligned slot. pxx put it in
the next eightbyte, so pxx calling gcc and gcc calling pxx both read the
wrong words (measured: 35863 and 1973175 for 5100). Caller: both C call
arms (direct and indirect) insert a pad slot (slotArg -1, `sub rsp, 8`)
before one at an odd eightbyte position. Callee: EmitParamSpillsForTarget
skips 8 bytes in the same case. Test c_int128_stack_arg_alignment, linked
with a gcc -c half: odd and even positions, two of them, one split by a
full register bank (the next long still takes r9), indirect calls, and
gcc calling pxx. Not covered: a by-value STRUCT whose alignment is 16.

## `(__int128)x` casts done 2026-11-23 (claude-pxx)

CUndeclaredTypeCastAhead took the built-in spellings for undeclared type
names. Test c_int128_cast_spellings, against gcc.

## int128 <-> float done 2026-11-23 (claude-pxx)

x86-64, both directions, both signednesses, double and float:
- To floating (I128ToDouble): one cvtsi2sd below 2^63; above, shift to 63
  bits with a sticky bit and add the shift to the exponent. Correctly
  rounded, as gcc's __floattidf; a float goes through the double, which is
  safe (53 >= 2*24+2).
- From floating (I128FromFloat): cvttsd2si below 2^63; above, the mantissa
  shifted by exponent - 1075, then negated. Truncates as __fixdfti.
- Mixed binops (arithmetic and compares) evaluate each side as double bits
  (I128MixedFloat / I128OperandAsDouble); a store into a float field or
  element converts while rdx:rax hold the value; an __int128 argument to a
  double parameter goes through the converting temp like any integer.

Tests c_int128_float_conversion (edges, ties, 2^127, and 4000-value
sweeps) and c_int128_float_mixed, both against gcc at -O0, -O2 and -O3.

## aarch64 done 2026-11-23 (claude-pxx)

gcc and clang have `__int128` on x86-64 and aarch64 only among pxx's
targets; on i386, arm32, riscv32 and xtensa both refuse it, and pxx now
refuses it there in gcc's words. wasm32 has it in clang only (gcc has no
wasm target), so with gcc as the reference it stays refused there.

aarch64 carries the x86-64 model in x0:x1 (ir_codegen_a64_i128.inc):
- Every operator, shifts, inline shift-subtract division, compares (a
  cmp/sbcs pair), and conversions to and from floating (ucvtf with a sticky
  bit; fcvtzs below 2^63). Mixed float binops and float stores convert
  while x0:x1 still hold the value. Conditions test both halves.
- The fixed sequences come from tools/a64_i128/snippets.s through gen.py
  (clang encodes them), and the comment on each word is its source line.
- AAPCS64: an even register pair and a 16-aligned stack slot (A64ArgAlign16,
  ABIA64ArgPlace). Arguments go through the aggregate loaders, and the
  return is in x0:x1. The calls in c_int128_aapcs64_calls were checked
  word by word against clang --target=aarch64-linux-gnu, as were the
  aligned-struct ones. There is no aarch64 linker here, so pxx<->clang
  objects were not linked.
- `__SIZEOF_INT128__` is defined on aarch64 too.

Every int128 test runs on aarch64 with gcc's x86-64 output (rows), at -O0,
-O2 and -O3 by hand.

## Structs aligned to 16 done 2026-11-23 (claude-pxx)

The gap the stack-alignment note left open was real. A struct holding an
__int128 after seven longs read 33166 where gcc reads 447, because pxx padded
only a bare __int128. SysVMemArgAlign16 now pads any argument whose
alignment is 16. On aarch64, ABIA64RecordClass refused alignment above 8, so
such a struct went by pointer where clang uses an even pair. It now
classifies alignment 16 and places it with A64ArgAlign16. Test
c_aligned16_struct_stack_arg: linked with gcc on x86-64, both directions;
one file on aarch64.

Found on the way, not fixed (a different ticket): on aarch64 pxx returns
every small struct (even `struct { long a, b; }`) through x8, where AAPCS64
and clang use x0:x1.
