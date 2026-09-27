---
track: C
prio: 45
type: bug
status: done
found: 2026-09-27
found-by: frankD
owner:
summary: "An array typedef whose element is a STRUCT, `typedef P PA[2];`, is not modelled: the typedef registration records dims only for non-record elements (cparser.inc, the `(tk <> tyRecord) and (tk <> tyPointer)` guard in the typedef parser). A local `PA x;` is REFUSED at `x[1].b` (\"no member named 'b'\"), which is loud; a struct MEMBER `PA ps;` is SILENTLY one element (`struct { char c; PA ps; int after; }` 16 bytes, gcc 24; `sizeof q.ps` 8, gcc 16). Measured on v443 and after bug-c-a-struct-field-that-points-at-an-array-typedef-has-no-pointee-dims, which fixed every non-record array-typedef member. CAUTION: pxx's own lib/crtl/include/stdarg.h declares `typedef struct __pxx_va_elem va_list[1];`, so modelling this changes va_list everywhere (params, va_start, va_copy, a va_list member); run the va_arg tests on every target before landing it."
---

# An array typedef of structs is not modelled

```c
typedef struct { int a, b; } P; typedef P PA[2];
struct Q { char c; PA ps; int after; };     /* pxx 16, gcc 24: ps is one P */
int main(void) { PA x; x[1].b = 9; }        /* pxx: no member named 'b' */
```

Measured 2026-09-27 on v443 (sha256 `f2b042c40f3b`) and on the build that fixed
array-typedef members of non-record element type. The struct builder and the
local declaration path already fold an array typedef's dims generically once
the typedef table has them (CTypedefDims/NDims), so the change is expected to
be at registration, and the risk is va_list (see summary).

## Resolution

Fixed 2026-09-27: the typedef registration records dims for a struct element
too. Every declaration path already folded them generically, as expected; a
48-row probe (members, locals, globals, designated and nested initializers,
arrays of the typedef, pointers to it, params, struct copies, unions, compound
literals) matched gcc except one row that is a different carrier, filed as
bug-c-a-function-returning-a-pointer-to-an-array-has-no-pointee-shape.

va_list: lib/crtl/include/stdarg.h now spells it `typedef struct
__pxx_va_elem va_list;`. Its `[1]` was dead text, and its own comment already
described the plain struct every target's ABI code is built around (abi.inc).
Behaviour is byte-for-byte what it was; the real-array question is filed as
bug-c-va-list-is-a-struct-not-an-array-of-one.

The fixture's compound-literal row found one more, independent of the
typedef: `((P[2]){{1,2},{3,4}})[1].b` read `.a` (also on v445), because
ResolveNodeRec's AN_INDEX arm had no compound-literal base. Added.

gcc-diffed in test/c_array_typedef_of_structs.c.
