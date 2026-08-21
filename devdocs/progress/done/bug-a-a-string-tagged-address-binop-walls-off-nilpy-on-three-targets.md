---
track: A
prio: 55
type: bug
blocked-by: []
summary: "i386, arm32 and aarch64 refuse a binop whose RESULT tag is not ordinal, even when both operands are machine words. A frozen-string value IS its address, so `PString(NativeInt(p[i]))^` is pointer arithmetic tagged tyString — and the refusal fires inside the NilPy runtime, so NO .npy program compiles for any 32-bit cross target. x86-64 has no such gate."
status: done
owner: claude-A
---

# A string-tagged address binop walls off NilPy on three targets

- **Track A** (`compiler/ir_codegen386.inc`, `_arm32.inc`, `_aarch64.inc` —
  the `IR_BINOP` integer path).
- Found 2026-08-21 while classifying the 61 i386 BUILDFAILs left over from the
  194-test record/variant sweep.

## Measured

53 of those 61 were the same one-line refusal, and it is not a record bug at
all — it is every NilPy program:

```
$ cat v1.npy
def main():
    a = 1
    b = 2
    c = a + b
    print(c)
main()

$ ./compiler/pascal26 --target=i386  v1.npy out
pascal26: error: target i386: non-integer binop not yet supported
$ ./compiler/pascal26 --target=arm32 v1.npy out
pascal26: error: target arm32: non-integer binop not yet supported
```

Nothing to do with the test's own code: the wall is in the **NilPy runtime**
(`compiler/builtin/pyeval.pas`), which every `.npy` program links. So the whole
NilPy frontend has been dark on the 32-bit cross targets — 53 tests that read as
"record/variant gaps" in a sweep were one gate in three backends.

## Root cause

`Error` at codegen time carries the LEXER's position, which pointed at an
unrelated line in another unit; the type kinds were not printed at all. Both are
fixed here (see below), and with them the wall reads:

```
target i386: non-integer binop not yet supported: ShortString
  (op token 71, operands NativeInt, NativeInt) in PyBindHostKwArgs
```

`PyBindHostKwArgs` contains `PString(NativeInt(pk[arity + p + 1]))^`. IR:

```
397: load_mem                      tk=Int64      { pk[i] }
399: binop  and $FFFFFFFF          tk=NativeInt  }
401: binop  xor $80000000          tk=NativeInt  }  NativeInt(x) on a 32-bit
403: binop  sub $80000000          tk=String     }  target: mask + sign-extend
404: store_sym                     tk=AnsiString
```

Node 403 is created as `tyNativeInt` by the narrowing-cast lowering and then
**retagged to `tyString` in place** by the `^` — deliberately, and documented in
`ir.inc`:

> A frozen-string / set value IS its address (no load). Present the address node
> with the value's frozen-string tag […] otherwise it carries IRLowerAddress's
> tyPointer tag and a consumer misreads the address as a raw pointer.

So the tag is right and the node is right. What is wrong is the gate:

```pascal
if not (TypeIsOrdinal(tk) or (tk = tyBoolean) or (tk = tyUnknown)) then
  Error('target i386: non-integer binop not yet supported');
```

**The result TAG does not choose the operation — the OPERANDS do.** The 64-bit
branch three lines above already knows this ("a comparison carries a Boolean
result tk, so key off the operands") and the same file forgot it one branch
later. x86-64 has no such gate anywhere in `IR_BINOP`; these three invented one.

## Fix

`BinopOperandIsMachineWord` (new, `symtab.inc`) — ordinal, pointer, `tyString`,
`tySet`, `tyUnknown`: the kinds whose value is a machine word in a register.
The gate now passes when the result tag is ordinal **or** both operands are
machine words. Genuinely non-word operands (variant, record, a float that
escaped the branch above) are still refused.

Diagnostics, in the same change and worth keeping on their own:

- the refusal now names the type kinds and the op token, and
- `CurProcNoteForError` (new, `symtab.inc`) appends `' in <proc>'`, because the
  `near:` context on a **codegen-time** Error is the lexer's stale position — it
  names whatever was tokenised last, routinely in a different unit. Without the
  proc name, locating a wall inside a builtin unit costs a bisect.

## Effect, and the walls behind it

| target | before | after |
| --- | --- | --- |
| **arm32** | refused | **builds** (then SIGILLs at runtime — next wall) |
| **i386** | refused | next wall: `symbol kind not supported yet (load)` |
| **aarch64** | refused | next wall: `aggregate result with more than 8 params` |
| riscv32 | `mmap not supported on bare-metal target` | unchanged |

None of those are this ticket. Filed as follow-ups so the NilPy-on-cross
campaign is visible rather than rediscovered by the next sweep.

## Gate

Self-host fixedpoint + `tools/gate.sh quick`; the 53-test dyn-array/interface
and 194-test record/variant cross differentials no worse than baseline.

## Resolution (2026-08-21)

Fixed as described above. Verified:

- The refusal is gone on all three targets. **arm32 now BUILDS a NilPy
  program** for the first time; i386 and aarch64 advance to different walls
  (tabulated above, filed as
  `bug-a-nilpy-on-cross-targets-four-remaining-walls`).
- 53-test dyn-array + interface differential over i386/arm32/aarch64/riscv32:
  **broke=0 fixed=0**.
- 194-test record + variant sweep on i386: **broke=0 fixed=0**. (`fixed=0` is
  expected — the 53 NilPy tests in that set still BUILDFAIL, one wall further
  along.)
- Self-host fixedpoint + `tools/gate.sh quick` GREEN.

The follow-up ticket carries the arm32 diagnosis this fix uncovered: the SIGILL
after a successful build is the NilPy driver emitting an **x86-64 entry stub**
unconditionally, and `EmitMmapArena` silently emitting x86-64 for i386, arm32
and aarch64 while refusing xtensa and riscv32. Same disease as this ticket, one
level up: a target dispatch that refuses some targets and lies to the rest.

## Log
- 2026-08-21 — resolved, commit PENDING-COMMIT.
