---
prio: 45  # auto
---

# C: `(float)*doubleptr` narrows to 0 when a single value is live (x86-64)

- **Type:** bug (C→IR / x86-64 float codegen). Track A/C.
- **Found:** 2026-07-08 (fable-abc), while writing the regression test for
  bug-c-sqlite-suite-runtime-segfault. Independent of that fix (this touches the
  double→single narrowing / xmm path, not the float→int truncation that was
  fixed).

## Symptom
Narrowing a DEREFERENCED `double *` to `float` yields 0.0 — but only when a
single/`float` value is also live in the function.

    float  xf = 1.5f;
    double gd = 42.25; double *dp = &gd;
    float  y  = (float)*dp;     /* y == 0.0, should be 42.25 */

## Minimal isolation (2026-07-08)
- `float s=1.5f; double d=42.25; float y=(float)d;`  → y=42.25 **OK**
  (narrowing a double LOCAL is fine).
- `double gd; double *dp=&gd; float y=(float)*dp;` with NO single live → OK.
- `float xf=1.5f; double *dp=&gd; float y=(float)*dp;` → **y=0.0** (BUG).
- `float x=*p; double y=*dp;` (no narrowing) → both correct.
Order-independent (declaring/using the single before or after doesn't matter).
So the trigger is the combination: a live single + `(float)`-narrowing of a
`double *` DEREFERENCE. sqlite itself is byte-identical to gcc, so its double
handling is fine — this is a specific narrow-of-deref pattern.

## Likely area
The double→single narrowing (`cvtsd2ss`) of a value loaded via a pointer deref,
with an xmm register clobbered/mis-scheduled when a single value is also
materialized. Compare the deref-load path (double bits in rax → xmm) against the
working local-double narrowing path; likely the deref value never reaches the
xmm that cvtsd2ss reads, or the single's xmm setup overwrites it.

## Gate
The three isolation cases above all print 42.25; make test + self-host
byte-identical; c-conformance + sqlite suite stay green.

## RESOLVED 2026-07-08 (fable-abc, Track A/C) — AN_PTR_CAST retagged the load width

Root cause: a float-class cast of a pointer dereference (`(float)*doubleptr` /
`(double)*floatptr`) lowered through AN_PTR_CAST (ir.inc ~3223), whose fall-
through `IRTk[Result] := ASTTk[node]` retags the operand node IN PLACE. When the
operand is a memory LOAD, that flips its width: an 8-byte double load became a
4-byte single load (and vice-versa), reading garbage (observed 0.0). Non-deref
operands (a BINOP/register value) only carry double bits, so the retag was
harmless there — which is why `(float)(d+0.0)` worked and the bug looked
"single-live dependent" (a red herring; `(float)*dp` fails with no single live).

Fix: don't reinterpret a float<->float cast. In pxx's model a float value lives
as double bits in a register at the operand load's NATURAL width, and a store to
a single/double slot narrows/keeps by DEST type — so leave the operand node
untouched (only ordinal casts retag). float<->int casts never reach here (routed
to the -203 Trunc / -206 Int intrinsics upstream).

Gates (all green): the isolation cases print 42.25 / 100.5; regression
test/cfloat_cast_deref_b196.c in test-core; test-c-conformance 204/0/16; sqlite
suite BYTE-IDENTICAL vs gcc; make test; self-host byte-identical; test-lua green.

## Log
- 2026-07-08 — resolved, commit 6d874c33.
