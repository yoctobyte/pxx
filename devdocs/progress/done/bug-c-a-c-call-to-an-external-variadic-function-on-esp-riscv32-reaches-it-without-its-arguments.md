---
slug: bug-c-a-c-call-to-an-external-variadic-function-on-esp-riscv32-reaches-it-without-its-arguments
track: C
prio: 30
type: bug
blocked-by: []
summary: "FIXED 2026-09-24. The slug is wrong about the mechanism: the arguments DID reach a0..a7 (riscv32) / a10.. (xtensa). What broke was a C STRING LITERAL passed to ANY function the program does not define (variadic or not): the riscv32 and xtensa backends skip a Pascal literal's length prefix on external calls, keyed on the IR_ARG wrapper's tyString tag, and the C frontend had already lowered the literal to const_str+prefix -- so the prefix was skipped twice and esp_rom_printf(\"ROM %d %d\\n\") printed \"d\". The skip now also requires the VALUE node to still be a string. Pascal external calls are byte-identical before and after.""
---

# A C call to an external variadic on ESP riscv32 loses its arguments

Found 2026-09-24 (frankS) while bringing up `feature-c-esp-conformance-coverage`.

## Repro (HEAD after the ESP C entry stub landed)

```c
extern int esp_rom_printf(const char *fmt, ...);
int main(void){ esp_rom_printf("ROM %d\n", 5); return 0; }
```

`tools/esp_run.sh --chip esp32c3 r.c` boots, IDF logs `Returned from
app_main()`, and **nothing** is printed. Controls in the same session, same
binary: `printf("hi %d\n", 42)` (crtl's printf) prints `hi 42`; a Pascal
`esp_rom_printf(fmt: string; v: Integer); external;` (non-variadic
declaration) prints fine in `examples/esp32/dns-c3`. So the stub, the link and
the ROM routine all work; the variadic call to a foreign definition does not.

## Measured vs inferred

- Measured: no output, on esp32c3 QEMU, with the three controls above.
- Inferred from `objdump -dr` of `main`: the arguments are stored into a block
  addressed through a `.bss` relocation before the call, the shape of pxx's own
  va marshalling, rather than being placed in a0/a1. Not traced through the
  codegen yet -- confirm before building on it.

## Scope to check

Whether the same holds on hosted targets for a C call into a `--dynlib` or
`-l` library's variadic (x86-64/aarch64 `printf` from libc when crtl is not the
provider) -- if so this is not ESP-specific and belongs in backlog-core.
xtensa cannot be checked yet: variadic C on the windowed ABI is refused.

## 2026-09-24 (frankS): FIXED -- and the inference above was wrong

The "Measured vs inferred" section above guessed the arguments went into a
.bss va block. **They did not**: the `.bss` stores it saw are crtl's errstr
table initialisation in `main`, and the call itself loads a0/a1/a2 correctly.
The fault is the FORMAT POINTER, which was `const_str + 8 + 8`.

- Mechanism: `ir_codegen_riscv32.inc` / `ir_codegen_xtensa.inc` skip the
  length prefix for `ProcExternal[procIdx] and TypeIsFrozenString(IRTk[argNode])`.
  An IR_ARG node is tagged tyString generically; the C frontend's value node is
  already `binop(const_str, 8)` of pointer type. Now the value node must also
  be a frozen string. x86-64/aarch64/arm32/i386 have no such skip.
- Not variadic-specific: `extern int ext_f(const char *)` took the same double
  skip. A `const char *p` variable never did.
- Why "nothing printed" on c3: the original repro's format `"ROM %d\n"` is 7
  chars, so +16 landed past its NUL. With `"ROM %d %d\n"` the unfixed compiler
  prints `d` on BOTH esp32c3 and esp32s3; the fixed one prints `ROM 5 77` on both
  (tools/esp_run.sh, QEMU).
- Pascal control: `pe.pas` with `external` cdecl/varargs calls on riscv32 esp,
  disassembly identical (ignoring the file header) before and after.
- Guard: test-emit-obj counts the double-skip pair in
  `test/c_string_literal_to_an_external_on_esp.c` on both ISAs (unfixed: 2 each).
