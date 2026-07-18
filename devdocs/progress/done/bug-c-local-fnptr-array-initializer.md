---
summary: "C LOCAL function-pointer array with brace initializer `int (*fp[2])(int) = {inc, dbl};` rejected ('expected C expression'); global form works"
type: bug
prio: 35
---

# C: local function-pointer-array initializer rejected

- **Type:** bug (Track C — C frontend local declarator/initializer, `cparser.inc`).
  Valid C rejected (compile fail).
- **Found:** 2026-07-18, gcc-differential sweep.

## Repro

```c
int inc(int x){return x+1;} int dbl(int x){return x*2;}
int main(void){
  int (*fp[2])(int) = {inc, dbl};   /* LOCAL array of function pointers, init */
  int v = 3, i;
  for(i=0;i<2;i++) v = fp[i](v);
  return v;                          /* 8 */
}
```

- **gcc:** 8.
- **pxx:** `error: expected C expression` near `inc` — the brace initializer of a
  LOCAL function-pointer array is not parsed.

## SHARPER DIAGNOSIS (2026-07-18)

The failure is at the DECLARATOR, not just the initializer: even
`int (*fp[2])(int);` with NO initializer fails (`error: unexpected token`). The
local declaration path (ParseCLocalDeclAST / the fn-ptr-local branch) does not
recognize the array-of-function-pointer declarator `(*name[N])(...)` at all —
ParseCDeclType captures it (CTypeFnPtrName + CTypeFnPtrArrLen, as the global path
uses at cparser.inc ~5857), but the LOCAL branch only allocates a single callable
pointer (CAllocDeclVar), ignoring the `[N]`. Building blocks that DO work: a
single fn-ptr local `int (*fp)(int) = inc;` (returns 42), and a fn-ptr-array
GLOBAL. So the fix is a LOCAL-path addition:
1. In the fn-ptr-local branch, when CTypeFnPtrArrLen >= 0, `AllocArray(name,
   tyPointer, 0, N-1)` and set `SymElemProcSig[idx] := CTypeProcSig` (element
   callable — `fp[i](args)` resolves via SymElemProcSig, see ParseCPostfixTail
   ~2299/2333).
2. Parse the optional `= { f0, f1, .. }` into per-element runtime assignments
   `AN_ASSIGN(AN_INDEX(fp, k), &fk)` (locals init at runtime, unlike the global
   PendingInit path). A bare function name lowers to its address (proven by the
   single-fnptr local init).

## Scope

The **GLOBAL** form is fine:

```c
int (*fp[2])(int) = {inc, dbl};   /* at file scope: works, verified */
```

So only the LOCAL declarator+initializer path for an array-of-function-pointers
mishandles the `{...}` list (likely the local-declarator init parser doesn't route
the array-of-fn-ptr element type to the function-name/address initializer the way
the global initializer path does).

## Acceptance

- The repro returns 8; C-conformance 220/220 + self-host byte-identical.
- A `test/*.c` regression.

## Log
- 2026-07-18 — resolved, commit 27c218ad.
