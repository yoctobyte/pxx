---
track: C
prio: 40
type: bug
status: done
found: 2026-09-27
found-by: frankD
owner:
summary: "On every target but x86-64, `__pxx_fesetround` is `return 0`: fesetround(FE_TOWARDZERO) reports success, fegetround still answers FE_TONEAREST and arithmetic keeps rounding to nearest (crtl_setjmp_oracle after-set=0). SILENT, same on v445."
---

# fesetround reports success on a target that ignores it

Found by the cross-target differential, 2026-09-27.

## Resolution (2026-09-28)

EmitCFenvStubs (compiler/cparser.inc) gains real stubs: i386 sets MXCSR and
the x87 control word (i386 keeps x87 for int64 conversions and Round);
aarch64 FPCR and arm32 FPSCR, RMode [23:22], whose encoding swaps FE's
up/down bits. riscv32 does its doubles in softfloat, which honours no mode,
so its setter refuses (nonzero) any mode but FE_TONEAREST, as wasm32's fenv.c
does. xtensa keeps the accept-and-ignore stub (no oracle here to check a
change against). Fixture `test/c_fesetround_rounds_or_refuses.c` (1/3,
-1/3 and 1e16+1 in each mode): v445 3 rows wrong per target, this build none.
