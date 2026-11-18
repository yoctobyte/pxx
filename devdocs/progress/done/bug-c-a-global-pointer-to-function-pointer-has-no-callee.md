---
track: C
tags: [cfront, fnptr, globals, rump, netbsd]
prio: 55
type: bug
blocked-by: []
summary: "A GLOBAL `int (**ops)(void *)` (NetBSD VOCALL, `(*((ops)[(off)]))(v)`) took the global fn-pointer path, which kept CTypeProcSig (-1 for this shape) and dropped the pointee's signature: no callee, \"expected ')'\" inside parentheses. Locals and parameters were right. Its initialiser `= vec + 1` / `= &vec[1]` was skipped, leaving the pointer nil. And `(*(p + i))(..)` had no CNodeProcSig arm. rump-pxx g34."
status: done
owner: pxx2
---

# A global pointer to a function pointer

- Global fn-pointer path: with no own signature and a pointee one, the symbol
  is a pointer to a pointer and carries SymElemProcSig (as the local path does).
- Its non-trivial initialiser replays like a pointer-to-array one (paDeferTok),
  in a program and in an object (.data).
- CNodeProcSig: `*(p + i)` / `*(p - i)` on such a symbol, one deref as callee.

Test: test/c_global_ptr_to_fnptr.c against gcc, x86-64 and i386.
