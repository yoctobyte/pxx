---
track: P
prio: 55
type: bug
blocked-by: []
status: done
owner: claude-A
commit: 3a107f008
summary: "`Writeln(pc - pc0)` on two `^Char` (or `^Byte`) pointers SEGFAULTED — the parser typed the difference node tyPointer, because TypeIsOrdinal reports tyPointer as ordinal so `p - q` matched the pointer-ARITHMETIC arm. Writeln then printed the difference as a null-terminated string from address 3. Assigning it to an integer first printed 3 correctly, and the IR lowering had typed it tyNativeInt all along."
---

# A pointer difference is typed as a pointer

Found 2026-08-22 by an FPC differential sweep over language shapes
(`fpc -Mobjfpc -O1` 3.2.2 vs pxx `3b980e9f0`).

## The measurement

```pascal
type TPC = ^Char;
var ac: array[0..7] of Char; pc, pc0: TPC; n: PtrInt;
...
n := pc - pc0; Writeln(n);    { fpc 3, pxx 3   }
Writeln(pc - pc0);            { fpc 3, pxx SIGSEGV }
```

| element type | via a variable | directly in Writeln |
| --- | --- | --- |
| `^Integer` | 3 | 3 |
| `^Int64` | 3 | 3 |
| `^Char` | 3 | **SIGSEGV** |
| `^Byte` | 3 | **SIGSEGV** |

Reproduced on `stable_linux_amd64/default/pinned`, so it is not a regression.

## Root cause

`TypeIsOrdinal` reports `tyPointer` as an ordinal — deliberately, it is a
pointer-width integer for every arithmetic purpose. So in `ParseSimpleExpr` the
arm

```pascal
else if ((op = tkPlus) or (op = tkMinus)) and
        (ASTTk[left] = Ord(tyPointer)) and
        TypeIsOrdinal(IntToTypeKind(ASTTk[right])) then
  ASTTk[node] := Ord(tyPointer)
```

claimed `p - q` as *pointer minus ordinal* and typed the result a POINTER.
The IR lowering has its own, correct arm — it detects two pointer operands,
subtracts, divides by the stride and tags the value `tyNativeInt`. The two
disagreed, and only the parser's answer reaches `Writeln`'s dispatch: a
`^Char`/`^Byte`-elemented pointer is a PChar there, so it printed the *value 3*
as a string address.

The reason `n := p - q` was fine is that an assignment converts through the
destination's type and never asks the node what it is. That is what kept a
crashing expression looking like it worked.

## The fix

One arm, placed above the pointer-arithmetic one: two `tyPointer` operands under
`-` produce `tyNativeInt` — the same type the lowering already assigned, so the
parser and the IR now agree. Pointer arithmetic (`p + n`, `p - n`, `n + p`) is
untouched.

## Verified against fpc

`^Integer`, `^Byte`, `^Char`, `^Int64` and `^TRec` differences, each through a
variable and directly in an expression; the difference composing as a number
(`(p - q) * 2 + 1`, `(p - q) > 2`); zero and negative differences; and pointer
arithmetic itself (`p0 + 5`, `Inc(p, -2)`) as control rows. Output
byte-identical to `fpc -Mobjfpc -O1`.

## Left open deliberately

FPC's `p - q` answers BYTES when either operand is an untyped `Pointer` — which
includes `@x`, since `{$TYPEDADDRESS OFF}` is FPC's default — and ELEMENTS when
both are the same typed pointer. pxx always answers elements. That is a dialect
choice rather than a defect, so it is filed as `decide-pointer-difference-unit`
(Track U) rather than changed here.

## Gate

`make compiler/pascal26` (self-host fixedpoint) + `tools/gate.sh quick` GREEN.
Test `test/test_pointer_difference_is_a_number.pas`, 18 assertions, wired into
`test-core`.
