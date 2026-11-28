---
slug: bug-gas-the-preprocessor-paint-byte-splits-an-asm-token
track: gas
prio: 70
type: bug
status: done
owner: pxx2
created: 2026-11-28
closed: 2026-11-28
found-by: pxx2 (libffi's x86/win64.S through ffi_cfi.h)
tags: [gasfront, cpreproc]
summary: "In a .S file, `#define cfi_startproc .cfi_startproc` then `cfi_startproc` failed with 'directive . is not supported'. The preprocessor marks an identifier its own macro produced with a #1 byte (blue paint, C 6.10.3.4). The C lexer skips it, but the assembler read `.`, #1, `cfi_startproc`. GasAssemble now drops #1 after preprocessing. Test: test/gas_frontend_libffi_shapes.S (`#define globl .globl`), check_gas_frontend.sh step 7."
---

# The preprocessor's paint byte split an assembly token

Reproduction, before the fix:

```
#define cfi_startproc .cfi_startproc
	.text
foo:	cfi_startproc
```

`pascal26 --emit-obj x.S x.o` gave "directive . is not supported". The
expansion contains the macro's own name, so the preprocessor paints it (#1
before the identifier) to stop re-expansion. That byte is meant for cfront's
lexer only. The fix strips it in GasAssemble right after CPreprocess, under
CPAsmSource. Assembly has no use for it, since nothing is re-scanned after
that point.
