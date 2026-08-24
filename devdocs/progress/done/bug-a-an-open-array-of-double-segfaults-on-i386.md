---
slug: bug-a-an-open-array-of-double-segfaults-on-i386
title: "An open array of Double segfaults on i386, before the callee runs a single line"
track: A
prio: 45
type: bug
blocked-by: []
status: done
owner: claude-A
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

## Log
- 2026-08-25 — resolved, commit PENDING-COMMIT.

---

# Resolution (2026-08-25)

**One rule, re-derived in four places, wrong in all four.** An open-array
parameter occupies ONE pointer-sized slot whatever its element type — the slot
holds a handle. `ABIParamSlotIsPointer(tk, isRef, isArray)` says exactly that,
answers `isArray` first, and is already what `ParamSize` and `AllocParam` read
when they lay the callee's frame out. Nothing on the i386 argument path asked
it; each site spelled its own rule from `TypeKind`, and `array of Double`
records the ELEMENT's kind, `tyDouble`.

So four sites widened a 64-bit-element open array to eight bytes:

| where | what it did |
| --- | --- |
| `ir_codegen386.inc` IR_CALL, float branch | ran `cvtsi2sd` over the dyn-array HANDLE and pushed the double bits |
| `ir_codegen386.inc` IR_CALL, 64-bit branch | pushed `edx:eax` for an `array of Int64` |
| `ir_codegen.inc` i386 spill, width walk | counted 8, shifting every EARLIER param's `[ebp+disp]` by four |
| `ir_codegen.inc` i386 spill, double copy | copied 8 bytes into a 4-byte slot, over the neighbour |

All four now call the oracle. The comment at the float branch had the diagnosis
exactly inverted — *"an open array of Double keeps the 8-byte push both sides
agree on"* — and the two sides never agreed: the callee's slot was four bytes
the whole time.

The visible symptoms, and why they looked unrelated:

- `LD(d)` — a dyn array of Double, a plain VARIABLE, a body that only calls
  `Length` — **faulted before its first statement**, because the low dword of a
  double bit pattern is not a pointer.
- `array of Int64` **survived by luck**: the 8-byte push put the handle in the
  low dword at the lower address, so the callee read it correctly and only the
  padding was wrong. `L64(q)` printing the right answer is what made the bug
  look float-specific.
- `H1(b: Int64; const a: array of Double)` returned **b + 2^32** — the spill's
  second dword landing on b's high word.
- `H4(b: Double; const a: array of Double; c: Integer)` **lost b entirely**.

That last pair is why the new test puts the open array in the MIDDLE of the
parameter list: a bad slot width is invisible when the open array is last, and
corrupts a different neighbour depending on what precedes it.

# Measurement

fpc 3.2.2 (`-Mobjfpc -O1`) as oracle, five targets (x86-64, i386, aarch64,
arm32, riscv32) — six element kinds by `Length` alone, six mixed-parameter
orderings, a by-value open array that mutates its copy, a `var Double` next to
an open array of Single, and 22 rows of dyn-array-valued ARGUMENTS from the
sibling ticket. **All green on all five.** Plus cdecl externals taking doubles
(`sin`, `pow`, `strlen`, `Format`) on x86-64/i386/aarch64/arm32, since two of
the four changed sites are on the external-call path.

Landed as `test/test_open_array_param_slot_is_a_handle.pas`, wired into BOTH
`test-core` and `test-i386` — the bug was i386-only, so the native recipe alone
would never have caught it. `test_call_result_as_open_array_argument` joins
`test-i386` too, now that it passes there.

Gate: `make compiler/pascal26` fixedpoint converged in 1 round,
`tools/gate.sh quick` GREEN.
