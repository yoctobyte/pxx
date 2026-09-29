---
track: N
prio: 20
type: bug
blocked-by: []
status: done
found-by: frankD (2026-09-29, the special-id census for bug-a-reallocmem-builds-only-on-x86-64); routed by frankuser
tags: [nilpy, wasm32, int, str, literal]
summary: "On wasm32, `int(\"42\")` and `str(\"ab\")` trapped with an out-of-bounds memory access, while `s = \"42\"; int(s)`, `float(\"42\")` and a user function taking a literal all worked. The -200/-201 intrinsics build their pylib call themselves and passed the literal raw, typed tyString. The ordinary call path first binds a literal to a hidden AnsiString local. On wasm32 the raw value is the frozen blob's address rather than an AnsiString, so pylib read a garbage header. The intrinsics now bind a literal the same way."
owner: ""
---

# `int("42")` and `str("ab")` trap on wasm32

```python
print(int("42"))   # CPython: 42    wasm32: wasm trap: out of bounds memory access
s = "42"
print(int(s))      # 42 on wasm32 too
```

## Cause and fix

The IR for `x = f("42")` stores the `const_str` into a hidden AnsiString
local and passes a load of it (`tk=23`). The -200 (`int`) and -201 (`str`)
arms in ir.inc build their `pystr_to_promo` / `pystr_to_int` / `pystr_of`
call by hand. `IRBindFreshStrArg` passes a literal through as a borrow, so the
argument was the bare `const_str`, tagged `tk=4`. x86-64, i386 and riscv32
give the right answer with it (measured; I did not trace why). wasm32's
`const_str` value is the frozen blob's own address (`WasmEmitConstStr`), and
the pylib routine faulted reading it as an AnsiString.

`IRLitAsAnsiStrArg` (next to `IRBindFreshStrArg`) binds an `AN_STR_LIT`
argument to a hidden AnsiString local, as the general call path does, and
the three arms pass that.

## Measured (2026-09-29, fixedpoint 1e81d502b3fc)

- `test/test_nilpy_int_and_str_of_a_string_literal.npy` covers:
  - `int` of one- and multi-digit literals, a padded negative literal and a
    30-digit literal (the arbitrary-precision path);
  - `str` of a literal and of `""`;
  - both inside expressions and an f-string.

  It equals CPython on x86-64, wasm32, i386 and riscv32. The previous compiler
  traps on wasm32 and passes on the others. The rows are x86-64, wasm32 and
  i386.
- Leak check (`-dPXX_ALLOC_CENSUS`, `tools/assert_no_leak.sh`): 1000 loop
  iterations of `int("42") + len(str("ab")) + int(<30 digits>) % 7` leave 12
  blocks live on x86-64 and 9 on wasm32, so the temp does not leak.
