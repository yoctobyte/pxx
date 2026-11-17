---
slug: feature-c-inline-asm-rump-x86-operand-forms
track: C
prio: 20
type: feature
status: done
created: 2026-11-17
found-by: pxx2 (NetBSD rump kernel through pxx), repros g14a, g14c, g20, g21 in ~/nilix/docs/rump-pxx/repros
tags: [cfront, inline-asm, x86-64, rump]
blocked-by: []
summary: "The x86-64 inline asm reader learned the forms NetBSD/rump's x86 headers use: the constraint letters \"qQ\", \"N\" alone, and \"=A\"; the %k and %q size modifiers; %[name] as a base register; a 32-bit base register meaning 32-bit addressing (the 0x67 prefix, as gcc+gas emit); the rep/repe/repne prefixes with movs/cmps/stos/lods/scas in all four widths; mov to and from the debug registers %dr0-%dr7; invpcid; and .hidden/.internal/.protected inside a function body, read and dropped. asm goto is still refused (see feature-c-inline-asm-goto)."
---

# Inline asm forms from rump's x86 headers

## Before and after
| repro | before | after |
|---|---|---|
| g14a `=qQ` | constraint refused | Q (a b c d) satisfies both alternatives |
| g14b `=m` | memory output refused | see feature-c-inline-asm-plus-m-read-write-memory-operand |
| g14c `"N"(0x80)` | refused | `i` with range 0..255 |
| g14c `"=A"` | refused | rax on x86-64, as gcc; i386 (edx:eax) refused by name |
| g14c `%k0` | bad % escape | %k = 32-bit, %q = 64-bit (beside %b %w %h) |
| g14c `1(%[x])` | refused | named operand as base; an int base is 32-bit addressing, 67 prefix |
| g14c `rep stosb` | unknown instruction | F3/F2 prefixes; movs cmps stos lods scas + b/w/l/q |
| g14c `movq %dr0,%0` | unknown register | 0F 21 / 0F 23, carried as AOP_CREG 16+n |
| g14c `asm goto` | refused | still refused, see feature-c-inline-asm-goto |
| g20 `invpcid` | unknown instruction | 66 0F 38 82 /r (an unused static inline still gets assembled) |
| g21 `.hidden` in a function | unknown instruction | read and dropped (no bytes; visibility only) |

## Notes
- `.hidden` has no effect in pxx objects. That is the same as pxx's handling of `__attribute__((visibility("hidden")))`. A pxx-built shared library would export the symbol where gcc's would not.
- g21 shows a separate front-end difference: a block-scope `extern ... __attribute__((__weak__))` comes out as a strong UND, where gcc's is weak. Reported to pxx2 (cfront).
- `.hidden` and the string ops are refused by name on the i386 text path, as `lock` is.

## Tests
- test/c_inline_asm_rump_operand_forms.c is run and compared with gcc at -O0 and -O2 (test-core rows c_asmrump26 and _o2).
- test/casm_kernel_system_instructions.c, compared byte for byte with gcc by tools/casm_sysinsn_vs_gcc.sh (63 instructions), gains k_invpcid, k_invpcid_rex, k_outb_n, and k_dr0/dr7/dr6_r9. The picker now also reads invpcid, outb, and movs touching %dbN.
