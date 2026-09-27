---
track: C
prio: 45
type: bug
status: open
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
