---
track: C
tags: [c, int128, attributes]
prio: 40
type: feature
blocked-by: []
summary: "__int128 works on x86-64 only. Still missing: other targets. Fixed 2026-11-23: stack-passed __int128 alignment, casts written `(__int128)x`, and int128<->float conversion. The narrow modes (QI/HI/SI/DI) work on typedefs, variables and members (2026-11-23)."
status: open
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
