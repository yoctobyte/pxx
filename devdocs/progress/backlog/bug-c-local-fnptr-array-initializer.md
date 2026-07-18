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
