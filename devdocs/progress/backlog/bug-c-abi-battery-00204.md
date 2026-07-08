
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
