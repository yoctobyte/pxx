---
slug: bug-a-c-a-struct-through-the-variadic-tail-is-passed-as-a-pointer
title: "A struct passed through the `...` of a C call is passed as a POINTER to a temp, not by value"
track: A
prio: 55
type: bug
status: open
created: 2026-09-02
found-by: frankD
owner:
summary: "The SIBLING ARM of the fixed bug-a-c-a-by-value-struct-parameter-is-passed-as-a-pointer-to-every-c-abi-callee: that ticket gave FIXED parameters the psABI treatment, and the VARIADIC TAIL still carries the old convention. A struct or union in a `...` slot occupies one GP/word slot holding the ADDRESS of a caller temp; gcc puts the aggregate's own bytes there. Self-consistent inside pxx (both halves are documented to agree -- see the `struct-by-value variadic arg` comment in cparser.inc), so no pxx-vs-pxx test can see it. Measured on x86-64 AND i386, so it is IR-level, not a backend choice. The concrete victim is `semctl(id, n, SETVAL, union semun)` -- crtl's SysV IPC semctl is correct against the ABI and returns wrong answers because of this. STRUCTURAL BLOCKER: IRLowerCallArg tags the temp's address `tyPointer`, so the record IDENTITY is gone by the time the backend's variadic-tail arm reads `IRTk[IRA[argNode]]`; a fixed param recovers it from the CALLEE declaration (ProcParamRecId), and a variadic slot has no callee declaration to recover it from."
---

# A struct through `...` is a pointer, not the bytes

## Repro — the receiving half reads the RAW SLOT, so it cannot agree by construction

`va_arg(ap, unsigned long)` on the callee side asks "what integer is in this
slot", which is why rows 1-4 below expose the convention instead of testing
whether pxx agrees with itself. Rows 5-6 are fixed params (the arm that was
fixed); rows 7-8 are pxx->pxx round-trips through `va_arg(ap, struct T)`, which
pass precisely because both halves share the wrong convention.

```c
union u8 { int val; void *buf; };  struct s8 { int a; int b; };
static unsigned long va_ul(int a, ...)
{ unsigned long x; va_list ap; va_start(ap,a); x = va_arg(ap, unsigned long); va_end(ap); return x; }
...
printf("1 %lu\n", (unsigned long)(unsigned int)va_ul(0, u8v));   /* u8v.val = 5 */
```

| row | arg | gcc (both widths) | pxx x86-64 | pxx i386 |
| --- | --- | --- | --- | --- |
| 1 | 8-byte union, variadic | `5` | `1852834208` | `4293475256` |
| 2 | 4-byte union, variadic | `6` | `1852834200` | `4293475248` |
| 3 | 8-byte struct, variadic | `7` | `1852834192` | `4293475240` |
| 4 | 4-byte struct, variadic | `8` | `1852834184` | `4293475232` |
| 5 | 8-byte union, FIXED param | `5` | `5` | `5` |
| 6 | 8-byte struct, FIXED param | `7` | `7` | `7` |
| 7 | pxx->pxx `va_arg(ap, union u8)` | `5` | `5` | `5` |
| 8 | pxx->pxx `va_arg(ap, struct s8)` | `7` | `7` | `7` |

The four wrong values descend by 8: consecutive stack temps. Repro kept at
`scratchpad/vap2.c`; compiler `b1014fb0eb1e` at commit `0baec7bad`.

## The three sites, and why the fix is not one line

1. **`compiler/ir.inc`, in `IRLowerCallArg`** — the `if CProgramMode then
   needTemp := True` arm (`grep -n 'C struct-by-value: a record param is by-ref'`),
   comment
   *"a record param is by-ref ABI (8-byte pointer slot), so ALWAYS copy the
   record to a temp and pass &temp"*. This is still RIGHT as a mechanism: the
   fixed-param fix kept the temp and taught the backend to load the eightbytes
   out of it. It is the tag that loses the information — `value := tmpAddr` is
   an `IR_LEA` tagged `Ord(tyPointer)`.
2. **`compiler/ir_codegen386.inc`, the `else` of `if i < Procs[procIdx].ParamCount`**
   in the cdecl argument loop (`grep -n 'the same promotion the counting loop applied'`, and
   the x86-64/aarch64/arm32/riscv32 equivalents) — it does
   `tk := IntToTypeKind(IRTk[IRA[argNode]])`, sees `tyPointer`, and slots one
   word. For `i < ParamCount` the same loop asks
   `ProcParamRecId[procIdx * MAX_PROC_PARAMS + i]` and expands the aggregate.
   **There is no `ProcParamRecId` for a slot with no param.**
3. **`compiler/cparser.inc`, the `vaRecId <> REC_NONE` arm of `__builtin_va_arg`**
   (`grep -n 'struct-by-value variadic arg'`) — the callee derefs TWICE, by
   design, and its comment names site 1 as the reason. Both halves must move
   together or nothing round-trips.

So the work is: carry the record id on the ARG (the arg is the only thing that
knows it in a variadic slot), classify it with the same `ABISysVArgPlace` /
`ceil(size/4)` oracles the fixed-param fix already validated against `gcc -S`,
expand it in every backend's tail arm, and drop the second deref in `va_arg`.

## Why nothing catches it today

The same reason its sibling went unseen, in the sibling's own words: *a
differential oracle only covers the population where the two implementations can
actually disagree, and a calling convention is agreed by construction inside one
implementation.* `test-c-abi-mixed-link` is the right gate and its 15 rows are
all fixed parameters. **The acceptance for this ticket is new MIXED-LINK rows
whose argument is in the `...` tail**, both directions, on x86-64 and i386.

## Gate

`make test-c-abi-mixed-link` green with the new variadic rows both directions on
both targets, plus A's usual `make test` + self-host fixedpoint + cross.

## Log
- 2026-09-02 — filed by frankD (Track C), found by building crtl's SysV IPC
  `semctl`, which takes `union semun` through `...` and is the canonical real
  program that needs this.
