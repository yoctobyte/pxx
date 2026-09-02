---
slug: bug-a-c-a-struct-through-the-variadic-tail-is-passed-as-a-pointer
title: "A struct passed through the `...` of a C call is passed as a POINTER to a temp, not by value"
track: A
prio: 55
type: bug
status: done
created: 2026-09-02
found-by: frankD
owner: frankA
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

## 2026-09-02 (frankA) — fixed on x86-64 and i386, with a mixed-link gate; three cross targets remain

Compiler `f34e52c193ae`. Every row of both repros now matches the gcc oracle on
both targets, and **the concrete victim this ticket was filed from works**:

```
union semun arg; arg.val = 42;
semctl(id, 0, SETVAL, arg);  printf("getval %d\n", semctl(id, 0, GETVAL, arg));

  gcc          getval 42
  pxx (now)    getval 42
  pxx (before) FAIL setval
```

### The three sites, done as the ticket specifies

1. **`ir.inc`, `IRLowerCallArg`** — the temp stays; what was missing is the
   record IDENTITY, so it is stamped on the value node the backends already
   inspect: `IRArgRecId[tmpAddr] := argRecId`, a new per-node side array beside
   `IRCallDest`. The ticket's structural blocker was exactly this and nothing
   more: `tyPointer` is the right tag for an `IR_LEA`, and the id had nowhere to
   travel.
2. **The placement loops.** x86-64 (`ir_codegen.inc`): the variadic arm's
   `aggRec := REC_NONE` becomes `aggRec := IRArgRecId[argNodeArr[i]]` with
   `tk := tyRecord`, and `ABISysVArgPlace` — the same oracle the fixed-param fix
   was validated against — does the rest, including the eightbyte expansion that
   was already written. i386 (`ir_codegen386.inc`): BOTH loops, the argBytes
   counting one and the emit one, take `ceil(RecSize/4)` words exactly as the
   fixed-param arm does. They had to move together; argBytes is also the
   saved-esp slot offset.
3. **`cparser.inc`, `__builtin_va_arg`.** The receiving half could not simply
   drop one deref, and that is the part worth recording: **an aggregate occupies
   one slot PER EIGHTBYTE, and a `struct { double a, b; }` lands in two XMM
   slots SIXTEEN bytes apart in the save area.** Nothing that returns a single
   address describes that. So x86-64 now materialises a temp
   (`AN_COMPOUND_LITERAL`, the same node a C99 record compound literal uses) and
   calls a new `__pxx_va_arg_agg(ap, dst, neight, ssemask, size)` in
   `lib/crtl/src/stdarg.c` that copies into it — the shape gcc emits. i386 has
   no register classes, so its slot really does hold the bytes: `RecSize` as the
   walk's step and one deref. `__pxx_va_arg_cross32`'s `step = (size <= 4) ? 4 : 8`
   became `(size + 3) & ~3` — identical for every scalar, and the only form that
   can describe a 24-byte struct.

**The all-or-nothing rule is in the helper, not in a per-slot walk.** SysV says
an aggregate whose eightbytes cannot ALL be placed in registers goes to memory
ENTIRELY; a slot-at-a-time receiver takes eightbyte 0 from the last register and
eightbyte 1 from the overflow area, which is a plausible wrong number rather
than a crash and needs five earlier variadic args to appear at all. The check is
done once, before any offset moves, from the same `neight`/`ssemask` the
frontend computed with `ABISysVRecordEightbytes`.

**`n < 0` — the classifier REFUSING a shape it does not model — keeps the old
pointer slot on BOTH sides.** The caller already fell through to it; the
receiver now does too. A refusal must not silently become a guess.

### The gate, and its positive control

`test-c-abi-mixed-link` gains **14 rows, both directions**, over the same six
shapes the fixed-param rows use (1 eightbyte / 2 eightbytes / MEMORY / all-SSE /
INTEGER+SSE / sub-word) plus a `full` pair that is the all-or-nothing boundary:
five named ints leave `gp_offset` at 40 and a 2-eightbyte INTEGER aggregate
needs 16. `PASS x86_64`, `PASS i386`, 2 of 2 targets measured.

**RUN POSITIVE CONTROL: the pre-fix compiler on the identical new rows produces
a binary that SEGFAULTS on both targets, rc=139, no output.** The rows can fail,
and they fail for this reason.

Also measured: `test-c-abi-cross` 12 PASS / 4 of 4 targets;
`test-c-abi-glibc-oracle` 2 PASS; `gate.sh quick` GREEN with the FPC seed
canary; self-host `converged after 1 round(s)`; and Pascal, Rust, Zig and BASIC
binaries byte-identical against the pre-change compiler, so the IR stamp reaches
only the C-ABI paths.

**NOT measured: `test-c-conformance` SKIPPED on all five targets** — the
c-testsuite is not installed here (`tools/install_lib_candidates.sh
c-testsuite`). A skip is not a pass and is recorded as a hole rather than
counted.

### What is left, and it is a different ticket

**aarch64, arm32 and riscv32 still pass the pointer.** Measured before and
after: arm32 and riscv32 print byte-identical output, and aarch64 differs only
in the four garbage stack addresses rows 1-4 were already printing — so they are
unchanged, not regressed, and still carry the defect. They have no mixed-link
oracle here (that harness runs x86_64 and i386 only), which is why they were not
done blind. Split out as
[[bug-a-c-the-variadic-struct-abi-is-still-a-pointer-on-aarch64-arm32-and-riscv32]].
- 2026-09-02 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
