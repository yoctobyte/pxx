---
prio: 60
---

# C: a function returning `float` (single) returns 0 on x86-64

- **Type:** bug (C float ABI — return path). Track C (C-frontend return
  lowering) / Track A if the codegen return slot is shared.
- **Found:** 2026-07-08 game-library ladder (feature-game-library-candidate-suite)
  while adding crtl float-math variants (fabsf/sqrtf/...); every one returned 0.

## Repro (x86-64, no headers)
```c
float twice(float x) { return x + x; }
int main(void){ float r = twice(2.5f); return r == 0.0f ? 10 : 42; }  /* gets 10 */
```
Narrower:
- `float pass(float x){return x;}` → 0.
- `int chk(float x){...}` (float PARAM, int return) → correct. So the param
  passes fine; the RETURN of a tySingle is lost/zeroed.
- `double` params+returns are correct throughout (lua/cJSON use double, which
  is why this stayed hidden — single-float returns are untested in the corpora).

## Impact
Blocks the crtl single-precision math family (fabsf/sqrtf/fminf/... all return
float) — NOT landed this session for that reason (would be silently 0). cglm
and most graphics C lean on float returns.

## Direction
Compare the C return-value lowering for tySingle against the Pascal `Single`
function-return path (project_single_first_class_done — Pascal Single returns
work), and against C double returns. Likely the C frontend tags the return
tyDouble→xmm0 correctly but a tySingle return reads/writes the wrong width or
register, or the narrowing convert is dropped.

## Gate
`float twice(float x){return x+x;}` returns 5.0; re-add + land the crtl
float-math variants (fabsf/sqrtf/sinf/cosf/floorf/ceilf/fminf/fmaxf/fmin/fmax/
modff — staged this session, reverted) with a smoke; c-conformance 00174/00175
family re-checked; self-host byte-identical.

## Log
- 2026-07-08 — resolved, commit e601151e.
