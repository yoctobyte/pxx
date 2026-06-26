# C: int<->float numeric cast + computed-double spill across branches

- **Type:** bug (float codegen) — Track C / backend
- **Opened:** 2026-06-26
- **Found-by:** lua float support (lmathlib/lstrlib/lobject). C float LITERAL
  lexing now works (clexer CLexFloatTail + AN_FLOAT_LIT, commit pending); these
  two value-level gaps remain.

## 1. int<->float numeric cast is a reinterpret, not a conversion
`(int)1.5` -> 0, `(double)i` -> wrong. ParseCUnary builds AN_PTR_CAST (retag /
bit-reinterpret) for ALL `(type)expr` casts (cparser.inc ~490). For a numeric
float<->int cast this must emit a real conversion (the backend already has
cvttsd2si / cvtsi2sd — used at stores and in float ops, ir_codegen.inc ~1310/2288).
Also the store path converts int->float but NOT float->int (`int i = d;` -> 0).
lua uses `cast_int(lua_Number)` etc. constantly. Fix: detect a numeric
float<->int cast (operand tk vs target tk) and route through a conversion (new
IR op, or a hidden-temp store that converts) on all targets.

## 2. A computed double held across multiple branches loses its value
```c
double a=1.5,b=2.5; double s=a+b;     /* 4.0 */
if (s>3.99 && s<4.01) if (e>14.9) return 42;   /* taken in gcc; pxx falls through */
```
A double from ARITHMETIC (vs literal-init) used in a nested-if / multi-compare
chain reads wrong — an xmm register is clobbered across the branch (no spill).
Literal-init doubles in the same shape work, so it is value-liveness across
branches, not lexing. Likely shared with the Pascal float path; reproduce there
too. Verify with the cfloat fixtures once fixed.

## DONE 2026-06-26 (Track C) — both parts fixed
Part 1 (cast, commit c0df24b3): numeric float<->int cast routes to the existing
cross-target intrinsics (-203 Trunc / -206 Int) instead of AN_PTR_CAST reinterpret.

Part 2 ROOT CAUSE was NOT spill/liveness (this ticket's guess was wrong). It was
`CBinResultTk` (cparser): float ARITHMETIC (`a+b`, `d*2`, …) was tagged tyInteger,
so the backend INTEGER-added the two IEEE bit patterns (0x3FF0..+0x3FF0..=0x7FE0..)
-> a garbage near-infinity double. That value compared > everything and cast to 0,
which looked like "computed double lost across branches". Fix: when either operand
is float, the arithmetic result type is the wider float (Extended>Double>Single).
Comparisons already return tyBoolean and key on operand type, so they came right
once arithmetic was correct.

Verified: `(int)(40.5+1.5)`==42, `s>41.9 && s<42.1` (computed s)==true. Self-host
byte-identical; Pascal float unaffected; C interop green. Unblocks the crtl printf
%f/%g float->decimal engine.
