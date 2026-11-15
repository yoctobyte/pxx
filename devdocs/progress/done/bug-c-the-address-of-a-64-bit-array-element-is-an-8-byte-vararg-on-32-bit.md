---
slug: bug-c-the-address-of-a-64-bit-array-element-is-an-8-byte-vararg-on-32-bit
track: C
prio: 80
type: bug
status: done
created: 2026-11-15
found-by: pxx (kernels seat): test/c_os_procfiles.c segfaulted under --os=minix and on Linux i386
tags: [cfront, silent-miscompile, i386, arm32, riscv32]
blocked-by: []
summary: "`sscanf(s, \"%llu %llu\", &v[0], &v[1])` with `unsigned long long v[]` segfaulted on i386 and riscv32 and read shifted values on arm32: IRLowerAddress tags IR_INDEX / IR_FIELD with the ELEMENT's type, the address-of arm retagged only float pointees as pointers, and the 32-bit variadic tail sizes an argument by that tag, so each address went out as an 8-byte pair. `&scalar` was right (IR_LEA is already tyPointer). Now a 64-bit ordinal pointee is retagged too when pointers are 4 bytes. Test: test/c_vararg_address_of_64bit_element.c in test-i386, test-arm32 and test-riscv32."
---

# The address of a 64-bit array element was an 8-byte variadic argument

Seen first as `stat: ...` missing from c_os_procfiles.c on Minix; the Linux
i386 build of the same file crashed at the same sscanf, which moved it out
of the translator. Old on the pin (before 5239196c40 at least).
