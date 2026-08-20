---
track: A
prio: 45
type: bug
blocked-by: []
summary: "`b := a` on a dynamic array aliases the handle WITHOUT retaining it on i386 and aarch64 — IR_STORE_SYM has no whole-dynamic-array case on either backend. Today that is a silent leak; the moment either target releases dyn arrays at scope exit it becomes a DOUBLE FREE (aarch64 segfaults on the second call). arm32 and riscv32 grew this arm already; these two were missed."
status: done
owner: claude-A
---

# i386 and aarch64 dynamic-array assignment has no store arm

- **Track A** (`compiler/ir_codegen386.inc`, `compiler/ir_codegen_aarch64.inc`,
  the `IR_STORE_SYM` lowering).
- Found 2026-08-21 while adding the missing dyn-array scope-exit release to the
  four non-x86-64 backends
  ([[bug-a-no-dyn-array-scope-exit-release-on-four-backends]]) — the release
  turned this latent bug into a crash, which is how it surfaced.

## Measured

```pascal
procedure PInt;
var a, b: array of Integer;
begin
  SetLength(a, 1); a[0] := 7; b := a;      { aliases; must RETAIN }
  Writeln('int ', b[0]);
end;
begin PInt; PInt; PInt; end.
```

With a scope-exit release present, this prints three lines on x86-64, arm32 and
riscv32, and **SIGSEGVs on the second call on aarch64**. i386 does not crash but
double-decrements a freed block's refcount word — silent corruption that happens
not to re-free, which is worse to find, not better.

Without the scope-exit release (today's shipped state on those two), the same
code merely leaks the block on every call. So this is currently invisible.

## Cause

`IR_STORE_SYM` in both backends has no `Syms[si].IsArray and (ArrLen = -1)` arm.

On **aarch64** the first test in `IR_STORE_SYM` is
`if Syms[si].TypeKind = tyAnsiString`, and an array's TypeKind IS its element
kind — so `array of string` is additionally routed through the SCALAR string
store, on top of the missing retain.

arm32 and riscv32 both have the arm (added by
`bug-a-arm32-dynamic-array-assignment-has-no-store-arm`): retain the new handle
via `PXXDynArrayIncRef`, publish it, release the old one through
`PXXDynArrayRelease` with the symbol's descriptor, with the move-semantics
carve-out for a fresh user-function result (`IRKind = IR_CALL` and `IRA >= 0`)
that already carries the +1. **That arm is the specification for this ticket** —
it is 40 lines, it is commented, and it explains its own ordering constraint
(it must precede the tyAnsiString arm).

## Order of work

This ticket first, then [[bug-a-no-dyn-array-scope-exit-release-on-four-backends]]
for i386 and aarch64 — that one landed for arm32 and riscv32 only, precisely
because they already retain. Doing them in the other order lands a double free.

## Gate

`da.pas` above prints three lines on both targets under `tools/run_target.sh`;
`test/test_dynarray_of_interfaces_assign.pas` 6/6; then the scope-exit arm can
land and `test/test_interface_containers.pas` should report `dyn: 2` there like
it does on x86-64, arm32 and riscv32. Self-host fixedpoint + `gate.sh quick`.


## Resolution 2026-08-21 (Track A)

Both backends got the arm, modelled on arm32's: retain the new handle via
`PXXDynArrayIncRef` (with the move-semantics carve-out for a fresh
user-function result, which already carries the +1), publish it, release the old
one through `PXXDynArrayRelease` with the symbol's layout descriptor. Placed
ahead of the `tyAnsiString` arm in both, because an array's TypeKind IS its
element kind.

**A second bug had to be fixed for aarch64 to work at all**, and it is the more
interesting half. `EmitStoreVarA64` has carried this since `b := a` was fixed on
the store side:

```pascal
{ A dynamic array's slot holds a pointer-sized heap handle, not an element.
  TypeSize(elementType) (e.g. 4 for `array of Integer`) would truncate the
  64-bit handle to 32 bits ... }
if Syms[idx].IsArray and (Syms[idx].ArrLen = -1) then sz := TARGET_PTR_SIZE;
```

`EmitLoadVarA64` — the mirror-image helper — did not. It stayed invisible
because nothing loaded a dyn-array handle through it; the moment something did,
it read half a pointer and segfaulted. That is precisely the sibling case
`devdocs/dev/normalise-dont-special-case.md` says to grep for before closing the
first half of a double case, and it went unchecked for as long as the guard has
existed. Fixed, with the comment saying so.

Measured, all four cross targets under `tools/run_target.sh`: the `b := a`
alias repro prints its three lines instead of SIGSEGVing on the second call
(aarch64) or silently double-decrementing a freed refcount (i386), and
`test_dynarray_of_interfaces_assign` is 6/6 everywhere. Independently, the
aarch64 load fix turned `test_dynarray_insert_delete` from a SIGSEGV at
assertion 13 into 35/35.

**What this does NOT unblock.** It closes row 1 of the audit table in
[[bug-a-no-dyn-array-scope-exit-release-on-four-backends]]. Row 2 — the
class/record FIELD store, where `IR_STORE_DYN` is x86-64 only and the other
backends take a non-retaining share path — is still open, and it is what makes
the scope-exit release unsafe. That ticket stays blocked, now on the audit
rather than on this.

Gate: `make compiler/pascal26` (fixedpoint) + `tools/gate.sh quick` GREEN, plus
the cross sweep above.

## Log
- 2026-08-21 — resolved, commit PENDING-COMMIT.
