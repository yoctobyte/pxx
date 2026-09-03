---
type: bug
track: A
prio: 75
status: done
summary: Under -dPXX_SHORTSTRING on i386, WriteLn of a record's string[N] field
  is a compile error, "target i386: write of this operand not yet supported";
  the ASSIGNMENT this ticket first blamed compiles and runs correctly. FIXED.
---

# i386 refuses a frozen record field write under the byte-prefix mode

**Blocks the phase-4 flip on i386.** The flip turns `-dPXX_SHORTSTRING` on
globally; today i386 cannot compile a record with a `string[N]` field being
assigned.

```pascal
type R = record f: string[10]; g: string[4]; end;
var r: R;
begin r.f := 'field'; end.
```

```
pascal26:2: error: target i386: write of this operand not yet supported
```

Compiles and runs correctly in the **default** mode on i386, and correctly in
BOTH modes on x86-64, arm32, aarch64 and riscv32. Also hit by an array of
records with a string field.

**This is an honest refusal, not a miscompile** — the backend says the operand
is unimplemented and stops, which is the right failure. It is a missing codegen
arm, so it should be cheap next to the wrong-value bugs in this family.

Found by running a 20-probe construct suite in both modes on all five runnable
targets; x86-64 alone shows nothing.


## The summary was wrong about which statement fails (2026-09-03)

`r.f := 'field'` is NOT the failing statement and never was. Measured at
`482b714d0` on i386 under the flag, the three-line body in the repro above
compiles, links and runs with exit 0 — the error comes from the `WriteLn(r.f)`
that the finding suite had beside it. "write" in the diagnostic is IR_WRITE,
i.e. `Write`/`WriteLn`, not an lvalue store; the original summary read it as the
verb and sent the next reader to the store path.

## Cause and fix

`compiler/ir_codegen386.inc`, the IR_WRITE operand dispatch: the frozen arm was
spelled `else if tk = tyString then`. **i386 was the last `= tyString` in an
IR_WRITE arm** — riscv32, arm32, aarch64, xtensa and wasm32 all say
`TypeIsFrozenString(tk)` and x86-64 does not reach this shape. A frozen operand
is tagged tyString only where the walker had a symbol to normalise through
`StrValTk`; a RECORD FIELD load keeps its storage kind, so `WriteLn(r.f)`
arrived as tyShortString, matched no arm, and fell to the catch-all Error.
`WriteLn(s)` for a bare `var s: string[10]` was correct in the same program,
which is why a variable-only suite saw nothing.

Widened to `TypeIsFrozenString(tk)`, matching the six other backends.

## Verified

Five targets (x86_64 native; i386/arm32/aarch64/riscv32 under qemu), BOTH modes,
value-asserted against a written `.expected` — not exit codes, not `Length()`:
record field, second field, and an `array[0..1] of R` element all print their
contents, are compared to a literal in both directions, and are indexed. All ten
cells PASS. The pre-fix binary refused to compile the i386 cells at all.

## The regression test fails on the pre-fix binary

`test/test_frozen_arg_and_field_write.pas` + `.expected`, wired for the native
sweep and the i386 / arm32 / aarch64 / riscv32 cross batteries, **both modes
each** (10 rows). Run against a rebuilt pre-fix compiler (`7f95d3b1c5c2`, the
same sha this session's first build produced, so it is the tree at
`482b714d0` and not a walked seed):

| row | pre-fix | post-fix |
| --- | --- | --- |
| i386 `-dPXX_SHORTSTRING` | **compile error** | PASS |
| i386 default | PASS | PASS |
| arm32 / aarch64 / riscv32, both modes | PASS | PASS |

The i386 DEFAULT row passes on the pre-fix binary and is kept deliberately: it
is a regression guard for the path that was never broken, not a detector, and
the test says so rather than letting a reader count it as coverage.

## Log
- 2026-09-03 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
