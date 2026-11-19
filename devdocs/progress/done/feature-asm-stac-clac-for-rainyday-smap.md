---
track: C
tags: [asm, gas, inline-asm, x86-64, kernel, rainyday]
prio: 30
type: feature
blocked-by: []
summary: "stac/clac (SMAP) are encoded by the GAS front end (.S) and in x86-64 inline asm, for Rainyday ticket 0024's copy_from_user/copy_to_user in a .S file with an __ex_table section. Before, both refused stac."
status: done
owner: pxx (Rainyday seat)
created: 2026-11-19
---

# stac/clac for Rainyday's SMAP user copies

Asked by the rainyday session (its ticket 0024: copy_from_user,
copy_to_user and strncpy_from_user as asm routines in a .S file, with one
__ex_table section of `.quad insn, fixup` pairs and stac/clac for SMAP).

- Measured 2026-11-19 on latest: `stac` refused in a .S file and in inline
  asm. A .S file's `.section __ex_table,"a"` with `.quad 1b, 2b` already
  assembled correctly.
- Done: 0F 01 CB / 0F 01 CA in gasfront.inc and asmenc.inc (AsmSystemOp,
  x86-64 only, like swapgs).
- Tests: tools/check_gas_frontend.sh step 5 (stac/clac byte-identical to
  gas) and step 6 (test/gas_frontend_extable.S: .text byte-identical to gas,
  the same two __ex_table R_X86_64_64 relocations, and the section is
  allocated). test/casm_kernel_system_instructions.c has k_stac/k_clac
  (tools/casm_sysinsn_vs_gcc.sh). Latest fails both checks.
- Not done, and not asked for: `.section`/`.previous` inside an inline asm
  template (Linux's _ASM_EXTABLE shape). Rainyday does not need it.
