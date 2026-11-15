---
slug: bug-c-a-pointer-to-a-function-pointer-declarator-is-a-function-pointer
track: C
prio: 60
type: bug
status: done
created: 2026-11-15
found-by: claude-opus (while testing the fn-pointer array member fix)
tags: [cfront, silent-miscompile]
blocked-by: []
summary: "`int (**pp)(int, int)` was typed as a plain function pointer: ParseCDeclType's function-pointer arm never counted the stars inside the `(*..name)` group. `(*pp)(a, b)` then called pp itself (the slot's address) and faulted. It only seemed to work when the initialiser came from a global function-pointer array. Now two stars publish the signature on the pointee channel (CTypePtrElemProcSig), as `ft *pp` does, and the local and struct-member paths read it; parameters already did. Test: test/c_fnptr_array_member.c (local, member, parameter)."
---

# A pointer-to-function-pointer declarator was a function pointer

The typedef spelling (`ft *pp`) was always right.
