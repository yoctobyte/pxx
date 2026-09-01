---
track: A
prio: 55
type: bug
status: open
found: 2026-09-01
found-by: frankC
summary: "`@`/address-of an EXTERNAL routine is refused outright on i386 (ir_codegen386.inc:4033) and xtensa (ir_codegen_xtensa.inc:4177): `error: @ on external routine not supported; wrap it in a local routine`. Nothing to do with aggregates or signatures -- minimised to `extern int f(int); typedef int (*fn)(int); fn p = f;`, which compiles on x86-64 and is refused on both. It is an honest refusal rather than a wrong answer, so no program miscompiles; it means a whole C idiom (a function pointer initialised from an external symbol -- syscall tables, vtable-style dispatch, sqlite's osOpen idiom) cannot be compiled for those targets at all. Found because test-c-abi-mixed-link's new function-pointer rows turned the i386 arm from a RUN failure into a COMPILE failure, which hides the state of the other 13 rows for whoever implements i386's aggregate ABI."
---

# The address of an external routine is refused on i386 and xtensa

```c
extern int gcc_thing(int);
typedef int (*fn)(int);
int use(void) { fn f = gcc_thing; return f(1); }
```

| target | result |
| --- | --- |
| x86-64 | compiles |
| i386 | `error: @ on external routine not supported; wrap it in a local routine` |
| xtensa | same message, `ir_codegen_xtensa.inc:4177` |

The suggested workaround in the message ("wrap it in a local routine") is not
available to a C program that receives the pointer from a table it does not
own, and it is not something a compiler can ask of hand-written C.

## Why it surfaced now, and the one thing to know before fixing

`test-c-abi-mixed-link` gained two rows that pass a struct through a function
POINTER, to close a hole in that gate (the indirect cdecl arm classified
arguments in its own loop and had not been converted). Those rows initialise a
fn-pointer from an `extern`, so the i386 arm of the gate now fails at COMPILE
time rather than at run time.

**That is a loss of information, not a new defect.** i386 was already red there
and stays red; but a compile failure means the other 13 rows report nothing, so
whoever implements i386's aggregate ABI cannot see which of them their work has
fixed. **Fixing this unblocks the diagnosis, not the feature** — worth doing
first for that reason rather than for its own weight.

x86-64 reaches the address through the GOT for an external
(`EmitExternalProcAddr` and the `PatchDynCallSites` relocation path). i386 has
the same dynamic machinery for CALLS; it is the address-of arm that was never
written.

## Related

- [[bug-a-c-a-by-value-struct-parameter-is-passed-as-a-pointer-to-every-c-abi-callee]]
  — the gate this surfaced under; its i386 half is still open.
- `test/cexternal_proc_addr_callable.c` asserts an external's address is
  CALLABLE and not merely non-nil; it is x86-64/aarch64 only for this reason.
