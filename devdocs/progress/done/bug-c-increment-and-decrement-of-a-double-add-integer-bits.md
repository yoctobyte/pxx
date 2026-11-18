---
slug: bug-c-increment-and-decrement-of-a-double-add-integer-bits
track: C
prio: 5
type: bug
status: done
created: 2026-11-18
found-by: pxx (Nilix seat), via awk in a pxx-built BusyBox; repro ~/nilix-payload/pxx-repros/double-incdec-2026-11-18/dinc.c
tags: [cfront, ir, float, busybox, awk, all-targets]
blocked-by: []
summary: "++ and -- on a float, double or long double were miscompiled on every target, and had been since at least the v455 freeze. The step was an integer constant typed as the operand's float type, and the IR reads a float-typed constant as an IEEE bit pattern. So n++ from 0 gave 4.94066e-324, a++ from 5 stayed 5, b-- gave NaN, and `while (k-- > 0)` never ended. awk's x++ printed 5 in every pxx BusyBox. On an array element or struct field (arr[i]++, v.number++), the stored address took the element's double type and the program crashed (SIGSEGV)."
---

# ++/-- on floating operands

gcc prints `6 6 2 6 3 5 5 3 3` for the repro. pxx printed `5 -nan 4.94066e-324 5 3 3 3 -nan -nan` with the current build, latest-35a7977144 and the v455 freeze master-a7c7ff69b7.

## Two defects, both in ir.inc AN_INCDEC
1. **The step.** `IR_CONST_INT foldK` was typed `argTk`. For a float operand it is now typed tyInteger, which is exactly what `x += 1` lowers to, and the float binop converts it. (A 64-bit bit pattern of 1.0 is not an option: the constant's value field dropped the high half in the IR dump.)
2. **The stored address.** IRLowerAddress types an element's or field's address with the element type (an IR_INDEX over a double array is tk=double). AN_INCDEC and the value-bearing AN_COMPOUND_ASSIGN store that address into a pointer temp, and the double-typed node did not survive the store as a pointer: arr[2]++ and v.number++ crashed. The new IRAddressAsPointer retypes a float-typed address node to tyPointer before it is stored.

## Test
test/c_float_increment_decrement.c, against gcc. It covers pre and post forms, as a statement and as a value; float, double and long double; an array element, a struct field directly and through a pointer, and `*p`; the `while (k-- > 0)` loop; and a double `for` counter. It matches on x86-64 at -O0 and -O2, i386, aarch64, arm32, riscv32 and xtensa. The test-core rows cover x86-64 (both), aarch64, i386 and xtensa.

BusyBox needs a rebuild to pick this up (pxx2 / pixx-cc told).
