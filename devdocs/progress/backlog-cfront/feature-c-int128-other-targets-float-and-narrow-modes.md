---
track: C
tags: [c, int128, attributes]
prio: 40
type: feature
blocked-by: []
summary: "__int128 works on x86-64 only. Still missing: other targets, int128<->float conversion, and 16-byte alignment of a stack-passed __int128. The narrow modes (QI/HI/SI/DI) work on typedefs, variables and members (2026-11-23)."
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
