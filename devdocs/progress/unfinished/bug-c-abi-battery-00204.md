---
prio: 55  # auto
---

# c-testsuite 00204: calling-convention battery (structs 1..17 bytes by value, HFAs, varargs)

- **Type:** bug (umbrella — run AFTER the other init/float tickets). Track C/A.
- **Found:** 2026-07-06 c-testsuite run.

## Failing test
- 00204 (527 lines): passes/returns structs of every size 1..17, HFA float
  structs, mixed varargs, by value AND through `...`. Output mismatch from the
  first "Arguments:" block (stack-passed args print garbage).
  Known-adjacent: v180 struct-by-value fix covered 8-byte records; this battery
  covers every size class + return-in-registers + varargs-of-struct.

## Approach
Re-run after bug-c-init-designated-and-nested + bug-c-float-single-precision
land (its structs use string/float inits); then diff section by section vs
.expected and file/fix per size class. x86-64 SysV first, then cross targets.

## Gate
Drop 00204.c from test/c-conformance/pxx.skip; runner green.


## Triage 2026-07-07
00204 COMPILES; the first "Arguments:" section prints BLANK where the struct
fields (`struct s1 { char x[1]; } = {"0"}` ... s17) should appear — so passing a
struct BY VALUE drops its data across the size classes. This is the whole
struct-by-value ABI battery (1..17-byte structs, HFA float structs, structs
through `...`), not a single bug. v180 fixed the 8-byte case; this exercises
every class + register-return + varargs-of-struct. Large, deep ABI work per size
class (SysV first, then cross) — focused multi-step session.

## 2026-07-08 (fable-c) — %Lf landed; scope narrowed to HFA float structs
Progress on 00204 after the init/float tickets cleared:
- **%Lf/%Le/%Lg** (long double, printf) — FIXED (crtl vformat now accepts the
  `L` length modifier; long double == double in pxx so it formats as %f).
  Cleared the long-double scalar-varargs block (lines ~27-64).
- **Verified already working**: struct-by-value <= 8 bytes (int/char members),
  struct RETURN <= 8 bytes, char-ARRAY structs (e.g. `struct{char s[9]}` by
  value + return) — the v180 struct-by-value arc covers these.
- **REMAINING core gap = HFA (homogeneous float aggregate) ABI**: a struct of
  floats/doubles (`struct{float x,y;}`) must pass/return in XMM registers per
  SysV (SSE-class eightbytes), but pxx classifies every aggregate as INTEGER
  (GP registers) -> `mkff()`/`useff()` read garbage
  (13743900737.0 instead of 34.1). This is the bulk of the residual 00204
  diff (the `NN.N,NN.N` and `0.0,0.0` blocks). Needs SysV eightbyte
  classification (INTEGER vs SSE per 8-byte chunk), XMM argument-register
  assignment for SSE eightbytes, and struct return in xmm0(:xmm1). Deep
  Track A codegen; the true "hardest slice" this ticket flagged. Left skipped
  under this ticket; the %Lf fix is committed separately.
