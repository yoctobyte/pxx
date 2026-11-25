---
slug: bug-c-a-typedef-enum-with-values-declares-only-its-first-name
track: C
prio: 60
type: bug
status: done
owner: pxx2
created: 2026-11-25
closed: 2026-11-25
found-by: pxx2 (libdrm for Path B Xorg)
tags: [cfront, typedef, enum]
summary: "`typedef enum { A = 1, B = 2 } F, *FP;` declared F and not FP (libdrm's drm_context_tFlagsPtr): `undeclared identifier 'flags'` for a `FP flags` parameter. CSplitDeclarators looked for the first declarator's initialiser `=` counting only parentheses and brackets, so the enum body's `A = 1` was taken for it and the split started at `A`. Braces now count as depth. Structs were unaffected (no `=` in their bodies), as was an enum without explicit values. Test c_xgaps26."
---

# A typedef enum with values declares only its first name

```c
typedef enum {
    DRM_CONTEXT_PRESERVED = 0x01,
    DRM_CONTEXT_2DONLY    = 0x02
} drm_context_tFlags, *drm_context_tFlagsPtr;
```
