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

## RESOLVED 2026-07-08 (fable-abc, Track A/C) — file-scope float array init was skipped

Root cause (traced via instrumenting stb's real_to_str): stb's `%f`/`%g` engine
multiplies by its power-of-ten DOUBLE tables (`stbsp__bot[23]` = {1e0..1e22},
`stbsp__top[]`, err tables). Those file-scope `const double[]` arrays read back as
ALL ZERO, so `raise_to_power10` returned ph=0 and the digit loop emitted nothing.

Reduced to `static double t[3]={1.5,2.5,3.5};` → reads {0,0,0} (scalar double
init was fine). ParseCGlobalVarDecl's flat array-init path required
`TypeIsOrdinal(baseTk)`, so a tyDouble/tySingle array fell through to the
brace-SKIP path and stayed BSS-zero.

Fix (compiler/cparser.inc): add an `allowFloat` param to
CBraceFlatIntInitCountAt (accept tkFloat elements) + a new CBraceIsFlatFloatInit,
and a flat-FLOAT-array init branch that emits one float PendingInit (Kind=3,
IEEE-754 double bits) per element — mirroring the scalar-float-global path —
handling `[k]=` designators and integer elements assigned into a float array.

Gates (all green): stb `%f/%.2f/%g/%e/width/precision/sign` BYTE-IDENTICAL vs
gcc; stb_sprintf_probe extended with the float subset (still exit 42);
regression test/cfloat_global_array_init_b197.c in test-core; c-conformance
204/0/16; sqlite suite byte-identical; make test; self-host byte-identical;
test-lua green.

## Log
- 2026-07-08 — resolved, commit d33dfe11.
