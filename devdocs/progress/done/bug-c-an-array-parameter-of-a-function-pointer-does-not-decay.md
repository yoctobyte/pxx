---
slug: bug-c-an-array-parameter-of-a-function-pointer-does-not-decay
track: C
prio: 70
type: bug
status: done
created: 2026-11-15
found-by: claude-opus (dropbear server segfault under --shared-runtime, reported by pixx-cc)
tags: [cfront, silent-miscompile, abi]
blocked-by: []
summary: "In a function-pointer signature an array parameter did not decay to a pointer (C 6.7.6.3p7). That covers an array typedef such as va_list (`__pxx_va_elem[1]` on x86-64) and `T a[]`. The indirect call passed the 24-byte block by value where the callee reads a pointer. dropbear's `_dropbear_log` hook (`void (*)(int, const char *, va_list)`) handed vsnprintf garbage, and the server segfaulted on its first log line. Named functions always decayed. CParseFnSigGroup is the one place both fn-pointer spellings parse their parameters, and it now decays both shapes. Test: test/c_fnptr_array_param.c (executable and --shared-runtime --link)."
---

# An array parameter of a function pointer did not decay

Older than the shared runtime: the compiler at 1f87a71427 and before faults on
the repro too. The self-contained dropbear build never reached that log call
on the paths its test drives; the shared-runtime build did.
