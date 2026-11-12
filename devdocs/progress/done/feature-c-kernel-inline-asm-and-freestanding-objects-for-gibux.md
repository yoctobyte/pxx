---
track: A
tags: [C]
prio: 30
type: feature
blocked-by: []
summary: "Gibux part B, first slice. C inline asm now has what a freestanding x86-64 kernel writes: cli/sti/hlt, in/out (dx and imm8, b/w/l), rdmsr/wrmsr, mov to and from cr0/2/3/4/8 and es/cs/ss/ds/fs/gs, lgdt/lidt/ltr/invlpg, swapgs/iretq/lretq/sysretq, fxsave64/fxrstor64/fninit/ldmxcsr/stmxcsr. Constraints: the 'Nd' port constraint, 'i'/'n' immediates (a constant expression), named operands %[name]. Numeric local labels: `1:` with `1f(%rip)`, and jmp/jcc 1b/2f. `--emit-obj --freestanding` gives an object with no .init_array/.fini_array, no crtl implementation pulled in by a header, and no signal alternate stack (implies --function-sections and --no-signals). It refuses a translation unit that needs run-time initialisation. 39 privileged instructions compared byte for byte with gcc+gas."
status: done
owner: unassigned
---

# C: kernel inline asm and freestanding objects (Gibux, part B first slice)

Requested by the owner, through the peer session, for Gibux (githome:gibux, a
small x86-64 kernel that must build with gcc and with pxx from the same
sources).

## Inline asm

### Encoder (asmenc.inc)

- AsmSystemOp encodes the system instructions.
- New operand kinds:
  - AOP_SREG, a segment register;
  - AOP_CREG, a control register;
  - AOP_RIPLBL, a `[rip+disp32]` to a local label. Its disp32 is patched once
    the instruction's end is known.
- These are x86-64 only. The i386 text sink does not list them, so it refuses
  them by name.

### AT&T reader (asmatt.inc)

- Segment and control register names.
- `%[name]`.
- `"i"` operands bind as `$value`, as gcc prints them.
- Numeric local labels resolve by gas's rule, using ordinals:
  - `Nb` is the latest definition at or before the reference;
  - `Nf` is the first definition after it.
- jmp/jcc to a local label always uses the rel32 form.
- in/out skip the suffix-versus-register check, because the port register dx
  is 16 bits whatever the suffix says.

### Constraints (cparser.inc)

- `"Nd"` is read as `"d"`. Taking dx is always one of the choices it allows,
  the same reasoning by which `g` is honoured as `r`.
- `"n"` is read as `"i"`.
- An `"i"` operand is evaluated with CEvalConstExpr at parse time, so
  `FOUR * 10` and `KERNEL_CS` work.
- An immediate output is refused.

## --freestanding (--emit-obj)

- It implies --function-sections, so a link keeps only the runtime helpers
  that are called.
- It implies --no-signals. The 32 KiB signal alternate stack was most of
  every object's .bss: 34,644 -> 1,340 B for an empty translation unit.
- It emits no .fini_array.
- A crtl header no longer pulls in its implementation. The kernel brings its
  own memcpy, as under gcc -ffreestanding. The pulled crtl also carried
  run-time-initialised tables, strsignal's among them.
- A translation unit whose init thunk is not empty is refused by name.

## Tests

- test/casm_kernel_user_mode_subset.c runs the half of this that works in user
  mode and compares its output with gcc's:
  - a far return through `leaq 1f(%rip)` and lretq;
  - segment register moves;
  - named operands and immediates;
  - `1b` and `2f` in one template.
- test/casm_kernel_system_instructions.c covers the privileged half. It is
  compiled by pxx and by gcc, and tools/casm_sysinsn_vs_gcc.sh compares the
  instructions objdump reads back: bytes for register forms, the mnemonic for
  frame-slot forms. 39 of 39 are the same.
- test/c_freestanding_object_has_no_runtime_hooks.c is checked by
  tools/check_freestanding_object.sh. The same file built without
  --freestanding fails all four checks.
- casm_nonempty_template_fails.c no longer expects `[a] "=r"` to be refused.
  Symbolic operands graduated into an acceptance test.
- All 40 inline-asm Makefile rows pass. The quick gate is GREEN.

## Not done here

The remaining Gibux work is in
backlog-cfront/feature-gibux-kernel-builds-with-pxx.md.
