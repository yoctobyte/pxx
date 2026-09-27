---
track: C
prio: 45
type: bug
status: open
found: 2026-09-27
found-by: frankD
owner:
summary: "The address of an array, `&a`, has no pointer-to-array type in an expression. It is stepped and dereferenced as if it pointed at ONE element: `&i4 + 1` steps 1 byte (gcc 16), `sizeof *&i4` and `sizeof(*(&i4))` are 4 (gcc 16), and for `mat4 a;` the stride is 1 and sizeof 4 (gcc 64). SILENT. The same on v444 (92139531ef89) and after the parenthesised-deref sizeof fix, so the defect predates both. A DECLARED pointer-to-array initialised from it (`int (*p)[4] = &i4;`) is fine: the shape comes from the declarator, not the `&` expression."
---

# The address of an array has no pointer-to-array type

```c
typedef float vec4[4]; typedef vec4 mat4[4];
mat4 a; int i4[4];
sizeof(*&a)                    /* pxx 4, gcc 64 */
sizeof(*(&i4))                 /* pxx 4, gcc 16 */
(char *)(&a + 1) - (char *)&a  /* pxx 1, gcc 64 */
(char *)(&i4 + 1) - (char *)&i4/* pxx 1, gcc 16 */
```

Measured 2026-09-27 with the pin v444 (sha256 `92139531ef89`) and with the build
that fixed regression-test-core-c-sizeof-ptr-to-array-field. Found while adding
parenthesised-deref rows to test/c_struct_member_of_array_typedef.c; the
`sizeof(*(&a))` row was left out of that fixture because of this ticket.

The single reader for "what does this pointer value point at" is ir.inc
`CPtrToArrShape`; it has arms for symbols, `m[i]`, `pp[i]`, `*pp` and fields, but
none for an AN_ADDR of an array-typed operand. Adding that arm there would feed
IRPointerStride, the decayed-deref sizeof (CSizeofDecayedDeref) and the
subscript arm at once. Check the plain `&a[0]` and `&s.arr` spellings with it.
