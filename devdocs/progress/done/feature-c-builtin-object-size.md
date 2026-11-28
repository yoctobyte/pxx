---
title: "C: __builtin_object_size (the unknown answer)"
status: done
owner: claude-dupwt
prio: 55
area: cfront
---

drm_connector.c (through LinuxKPI's string/copy-size checks) calls
__builtin_object_size, which pxx did not know: "call to undeclared function".
Found in the GPU-driver census (feature-nodisx-linux-gpu-drivers-built-by-pxx).

pxx tracks no object sizes, so __builtin_object_size(p, t) and
__builtin_dynamic_object_size give gcc's "unknown" answer: (size_t)-1 for
types 0 and 1, and 0 for 2 and 3. Every fortify-style check then takes its
no-check path, so the answer is safe: it never refuses a valid copy, and it
only declines to catch an overflow gcc might have caught. p is not evaluated.
The builtin is a predefined macro beside the overflow builtins (cpreproc.inc).

gcc knows the size of `&k` even at -O0, so the test asserts "exact or unknown"
rather than gcc's number (row c_movnt26).
