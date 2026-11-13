---
track: C
tags: [c, x86-64, abi, sysv, dropbear]
prio: 50
type: bug
blocked-by: []
summary: "A struct passed by value that SysV puts on the stack (MEMORY class) counted one call slot per eightbyte, against a cap of 128. libcrux's 2400-byte MlKemPrivateKey (dropbear's mlkem768.c) needs 300, so the call was refused with \"C call: too many argument slots\". It now takes ONE slot whose push loop copies every eightbyte; the bytes emitted for smaller aggregates are unchanged."
status: done
owner: claude
---

# A struct over 1 KiB by value ran out of call slots

Found building dropbear 2026.94 ([[feature-c-dropbear-builds-with-pxx]]).
`libcrux_mlkem768_sha3.h` passes `libcrux_ml_kem_types_MlKemPrivateKey_55`
(`uint8_t value[2400]`) and the 1184-byte public key by value.

**Cause.** In `compiler/ir_codegen.inc`, both slot loops (the indirect cdecl
call and the direct C call) gave a MEMORY-class aggregate one slot per
eightbyte. The stack-push loop already copies an aggregate from its highest
eightbyte down, so those extra slots only counted toward `MAX_CALL_ARGS`.

**Fix.** A MEMORY-class aggregate with more than one eightbyte now takes one
slot. `slotSrcOff` is set to its highest eightbyte and `mStack` is advanced
by the full eightbyte count. The pushes and their order are the same, so the
bytes do not change. Four existing by-value tests were checked byte-identical
against the compiler from before the change.

**Test.** `test/c_big_struct_by_value_and_cmov.c` (row `c_bigsbv26`, against
gcc -O0). It passes the struct directly, through a function pointer, and
between register arguments on both sides. It also returns a struct of both
keys by value. It reads bytes at the start, middle and end, so a short or
shifted copy shows.
