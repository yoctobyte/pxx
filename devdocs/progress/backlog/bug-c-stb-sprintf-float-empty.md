---
prio: 40
---

# stb_sprintf %f/%g produces empty output under pxx

- **Type:** bug (discovery — stb float engine vs pxx C runtime). Track C / A.
- **Found:** 2026-07-08 game-library ladder (feature-game-library-candidate-suite),
  after bug-c-inline-fnptr-param-call made stb_sprintf compile + its callback
  engine run (integer/hex/string formatting is byte-exact vs gcc).

## Symptom
`stbsp_sprintf(b, "%f", 3.5)` yields "" (empty). Integer/hex/string/width all
match gcc; only the float conversions produce nothing. gcc-built stb gives
"3.500000".

## Suspected mechanism
stb_sprintf's float path (stbsp__real_to_str / stbsp__real_to_parts) does raw
double bit manipulation (union-punning the double to uint64, a big static
stbsp__powten[] double table, __int64 mantissa math). Likely culprits: the
double-bit union pun, the 512-entry double lookup table
(global float-array init — cf. bug-c-multidim-ordinal-global-init /
global float array init), or 64-bit mantissa arithmetic. Needs the same
gdb-bt -> TU-line -> minimal-repro method the tcc/zlib arcs used.

## Gate
`stbsp_sprintf(b,"%f",3.5)` == "3.500000"; extend test/gamelib/stb_sprintf_probe.c
to the float subset; no regression.
