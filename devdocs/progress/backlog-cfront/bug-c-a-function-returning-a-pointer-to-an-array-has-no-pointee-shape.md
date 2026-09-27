---
track: C
prio: 45
type: bug
status: open
found: 2026-09-27
found-by: frankD
owner:
summary: "A function returning a pointer to an array -- `vec4 *f(void)`, `mat4 *f(void)`, `int (*f(void))[4]`, `PA *f(void)` for a struct-array typedef -- returns the right address, but no carrier records what it points at: `sizeof *f()` is 4 (gcc 16; 64 for mat4), `f() + 1` steps 4 (gcc 16), `(*f())[2]` and `f()[0][2][2]` read the wrong element. SILENT, and the same on v445 (caf21ac399f1). The symbol, field and element carriers are right; the Procs table has ProcRetPtrElemTk/Rec but no pointee dims."
---

# A function returning a pointer to an array has no pointee shape

```c
typedef float vec4[4]; typedef vec4 mat4[4];
vec4 gv; mat4 gm;
static vec4 *fv(void) { return &gv; }
static mat4 *fm(void) { return &gm; }
static int (*fi(void))[4] { static int a[4] = {5,6,7,8}; return &a; }
sizeof(*fv())                     /* pxx 4, gcc 16 */
sizeof *fm()                      /* pxx 4, gcc 64 */
(char *)(fm() + 1) - (char *)fm() /* pxx 4, gcc 64 */
(*fi())[2]                        /* pxx 1, gcc 7  */
```

Measured 2026-09-27 on v445 (sha256 `caf21ac399f1`) and after
bug-c-the-address-of-an-array-has-no-pointer-to-array-type. The fix is a third
carrier beside the symbol (SymPtrElem*) and field (UFldPtrElem*) ones: store the
pointee's length and dims per procedure at the declaration, and give ir.inc
`CPtrToArrShape` an AN_CALL arm, which feeds the `*` decay, the subscript
flatten, IRPointerStride and the sizeof fallback at once. Known-issues row:
"C: a function returning a pointer to an array steps it one element at a time".
