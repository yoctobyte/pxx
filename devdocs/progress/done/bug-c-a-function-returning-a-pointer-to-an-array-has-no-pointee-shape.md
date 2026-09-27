---
track: C
prio: 45
type: bug
status: done
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

## Resolution (2026-09-27)

As proposed: a third carrier, `ProcRetPtrElemArrLen/NDims/Dims` per procedure,
filled in `ParseCSubroutine` from the declarator's `CTypePtrElem*`, and an
AN_CALL arm in ir.inc `CPtrToArrShape` (plus AN_CALL in `IRPointerStride`'s
top arm). Two more pieces were needed:

- a full subscript over a call base (`fm()[0][2][3]`) is lowered as the
  decayed-row arm lowers a row, `*(f() + flat*elem)`: an AN_INDEX over the
  call stepped by the whole pointee once the stride knew it;
- `int (*f(void))[4]` was parsed as a function returning a FUNCTION pointer
  (the `[4]` read as an empty parameter list); the fn-pointer declarator branch
  now reads the dims when a `[` follows the `(*name(params))` group.

Found on the way and fixed with it: `typedef struct P PA[3];` and
`typedef struct {..} QA[3];` dropped their dims (the two struct arms of
`ParseCTypedef` skipped them), so `sizeof(PA)` was 8 (gcc 24). The dims reader
is now `CTypedefReadDims`, shared by all three arms.

Fixture `test/c_function_returning_pointer_to_array.c` (48 rows, gcc-diffed,
native and i386): v445 answers 41 of them wrong.
