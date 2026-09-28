---
track: A
prio: 60
type: bug
status: done
found: 2026-09-28
found-by: frankD
owner:
summary: "CRASH, i386/arm32/riscv32. `Call(@b.M)` -- a method reference given directly to an `of object` parameter -- segfaulted; `f := @b.M; Call(f)` was right. IRLowerCallArg's methodref arm passed the {Code, Data} temp's ADDRESS, the 64-bit record-by-reference ABI; on a 32-bit target the pair is 8 bytes and a 5..8-byte record argument travels as its VALUE (Arg32Class A32_RECORD). v446 crashes test_method_pointer_arg_b361 and test_methodref_arg_to_a_method_call on all three."
---

# A method-reference argument is passed by address on 32-bit targets

Found by the Pascal cross-target differential (both tests green natively).

## Resolution (2026-09-28)

The methodref arm still materialises the pair with IRMethodRefToTemp, and when
the parameter is not by reference (`not isRefArg` -- the pair fits the by-value
band) it passes the temp's value with an IR_LOAD_SYM tagged tyRecord, exactly
the node `Call(f)` over a variable lowers to. 64-bit targets, where the 16-byte
pair is promoted to by-ref, are unchanged. Both tests now run cross in
test-core.
