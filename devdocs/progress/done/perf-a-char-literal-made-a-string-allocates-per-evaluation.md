---
track: core
prio: 40
type: perf
blocked-by: []
summary: "On x86-64, a one-char literal made into an AnsiString (`s := 'x'`, 'x' passed to a string parameter) called PXXStrFromLit, a heap block per evaluation, while every longer literal already took the static pool block at -O2. The parser types a one-char literal as tyChar (IR_CONST_INT), so EmitStaticLitHandle never saw it. EmitStaticCharHandle now interns Chr(v) and loads the static handle at all six char-to-AnsiString sites. managed_calls benchmark: 717.3M -> 471.8M instructions (-34%)."
status: done
owner: unassigned
---

# A char literal made a string allocates per evaluation

## Found

This came out of the 2026-11-12 benchmark set (callgrind instruction counts,
see "Measured"). The managed_calls profile had PXXAlloc at 17.5%,
PXXStrFromLit at 9.85% and PXXFree at 11.7%. Most of those calls came from
`s := 'x'`.

`s := 'x'` emitted this sequence:

    mov eax, 'x' ; push rax ; mov rsi, rsp ; mov rdi, 1 ; call PXXStrFromLit

That is a fresh heap block for a constant. `s := 'xy'` loads the static
handle instead (EmitStaticLitHandle, -O2 and up). The difference is the
literal's type. The parser makes a one-char literal tyChar, an IR_CONST_INT,
and EmitStaticLitHandle accepts only IR_CONST_STR.

## Fix

`EmitStaticCharHandle(node)` in ir_codegen.inc runs only under these
conditions:

- the optimisation level is -O2 or higher, as for EmitStaticLitHandle;
- the node is IR_CONST_INT;
- the node's type is tyChar;
- the value is in 0..255.

When they hold, it interns `Chr(v)` and loads `@data + Offset + 8`, the
literal's static managed handle. It emits no retain, for the same reason
EmitStaticLitHandle emits none: the release paths refuse a static block.
Otherwise it emits nothing, and the PXXStrFromLit arm runs as before.

There are six char-to-AnsiString sites:

- two stores (global/local and field);
- ordered arguments;
- direct-call arguments;
- constructor arguments;
- method/indirect arguments.

At the argument sites, IREmitNode has already loaded the char into rax.
That `mov` stays as a dead instruction, the same trade
EmitAnsiStrFromInlineStringOf makes.

x86-64 only. The other backends keep calling the runtime. Their twins
(EmitStaticLitHandle386, EmitStaticLitHandleA64, and the arm32, riscv32 and
xtensa arms) are the place to repeat this when it is worth it.

## Measured

Instruction counts (Ir) under callgrind, base = master fd876a1891:

| benchmark | base | after |
|---|---|---|
| managed_calls (-O2) | 717,281,774 | 471,795,307 (-34.2%) |
| managed_calls -O3 | 703,579,300 | 467,007,130 (-33.6%) |
| compiler compiling lib_charset | 2,380,822,774 | 2,379,478,968 |
| nilpy_primitives | 1,004,133,357 | 1,004,128,586 |

Read the managed_calls row as a ceiling. It is the scratch benchmark written
for this round, and one of its four routines assigns two one-char literals on
every pass. The compiler workload, an ordinary large program, moves by 0.06%.

fib, nbody, mandelbrot, raytracer and py_iter did not change. The compiled
compiler's code is 100 bytes smaller on lib_charset; its data is 80 bytes
larger, from the interned one-char literals.

## Checked

- The self-rebuild reaches a fixedpoint.
- A/B over a 159-source x86-64 sample at -O2: 102 SAME, 35 DIFF, 22 BOTHFAIL.
  Every DIFF pair runs with identical output and exit code.
- test/test_a_char_literal_made_a_string_is_a_static_block.pas checks the
  following, with output identical to fpc's:
  - copy-on-write after `s := 'x'`, so the literal is unchanged on the next
    loop pass;
  - #0 and #255;
  - by-value callees that write into or rebind the argument;
  - method and procedure-variable calls.

  Its census row passes on both compilers. The census reports on a geometric
  threshold, so these counts are the last report line, not exact totals:

  | | allocs | live |
  |---|---|---|
  | base | ~91.5k | 5 |
  | after | ~72.3k | 4 |
- Full tier: see the commit.
