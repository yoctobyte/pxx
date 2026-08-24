---
slug: bug-a-an-open-array-of-double-segfaults-on-i386
title: "An open array of Double segfaults on i386, before the callee runs a single line"
track: A
prio: 45
type: bug
blocked-by: []
status: backlog_new
owner: ""
created: 2026-08-25
summary: "`function LenD(const a: array of Double): Integer; begin Result := Length(a); end;` called with a dyn array of Double segfaults on --target=i386. Not a call-result problem and not new: it reproduces on the PINNED compiler, with a plain VARIABLE argument, in a body that only asks for Length(). The x86-64, aarch64, arm32 and riscv32 builds of the identical source all print the right answer, so it is the i386 open-array argument ABI, not the frontend."
---

# Repro

```pascal
program i4;
type TDA = array of Double;
function LenD(const a: array of Double): Integer; begin Result := Length(a); end;
var dd: TDA;
begin
  SetLength(dd, 2); dd[0]:=1.5; dd[1]:=2.5;
  WriteLn('len var  : ', LenD(dd));
end.
```

```
$ pxx --target=i386 i4.pas i4 && tools/run_target.sh i386 i4
len var  : Segmentation fault
```

Identical output from `stable_linux_amd64/default/pinned` and from HEAD — this
is **not** a regression from the call-result work
(`bug-p-a-call-result-is-refused-as-a-const-open-array-argument`, resolved
2026-08-25); that fix made every one of these rows correct on x86-64, aarch64,
arm32 and riscv32, and left i386 exactly as it already was.

# What is and is not implicated

- Not the ELEMENT KIND alone: `array of Integer` was not tried in the same
  shape and should be, first thing — if Integer works and Double does not, the
  suspect is how the i386 backend passes the pair (handle, high) when the
  element is 8 bytes.
- Not the argument SHAPE: the failing call passes a plain dyn-array VARIABLE.
  The call-result and `Copy()` forms are strictly harder and were the subject of
  the resolved ticket; they are irrelevant here.
- Not the callee's body: `Length(a)` is the whole of it, so the fault is at or
  before the prologue's read of the open-array high/handle pair.
- The x86-64 path is fine, so any shared-IR explanation has to say why only the
  32-bit x86 lowering breaks while arm32 and riscv32 (also 32-bit) do not.

# Why it stayed hidden

`test/test_call_result_as_open_array_argument.pas` is wired into `test-core`,
which is native-only, and the 22-row differential that produced it was run on
x86-64 first. The i386 fault only appeared on the cross sweep, which is where
this ticket comes from. The test is deliberately NOT added to a cross-target
list until this is fixed — adding it would land a known red.

# First moves

1. Bisect the element kind: Integer / Int64 / Single / Double / a record, same
   one-line `Length(a)` body, `--target=i386`.
2. If it is width-dependent, read the i386 open-array argument emission next to
   the arm32 one, which works.
3. `-g` + gdb under qemu on the i386 binary will name the faulting instruction
   directly; the fault is early enough that a disassembly of the prologue may
   be quicker than either.
