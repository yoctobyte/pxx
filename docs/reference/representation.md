---
title: Representation contract
order: 92
---

# Representation contract

How much space a value takes, how an array of it strides, and what lands on
disk or on a wire.

**This page is the specification, not a report.** There is no formal standard
for most of what is below: Delphi made choices, FPC followed them, and PXX
takes FPC's where they are settled. So when you need to know whether you may
rely on a size, there is nothing else to appeal to — which means this page owes
you a distinction that a "how it works today" page does not:

- **Guaranteed** rows are part of the contract. Code may depend on them, and
  changing one is a breaking change.
- **Incidental** rows are true today and are not promises. They are marked.

Every number here was measured, not derived, with the compiler named at the
[bottom of the page](#what-these-numbers-were-measured-with).

## How to read a row

Three separate questions, and the second and third are the ones that bite:

| | |
| --- | --- |
| **size** | what `SizeOf` answers |
| **stride** | how far apart consecutive elements of an `array of T` sit |
| **on disk** | what one record of `file of T` occupies |

For every type on this page all three are the same number. That is itself part
of the contract: **PXX does not pad array elements beyond their own size, and a
typed file writes exactly `SizeOf` per record.** Where a type has no `file of`
support at all, the row says so.

## Scalars

Guaranteed, and identical on x86-64, i386, arm32, aarch64 and riscv32:

| Type | Size |
| --- | --- |
| `Boolean`, `Byte`, `ShortInt`, `Char` | 1 |
| `WideChar`, `Word`, `SmallInt` | 2 |
| `Integer`, `LongInt`, `Cardinal`, `Single` | 4 |
| `Int64`, `QWord`, `Double` | 8 |

`Integer` is 4 bytes on every target, including the 64-bit ones. If you want a
width that follows the machine, name `NativeInt` or `PtrInt`.

Two rows follow the target's pointer width instead — guaranteed to *be* the
pointer width, not guaranteed to be any particular number:

| Type | 32-bit targets | 64-bit targets |
| --- | --- | --- |
| `Pointer`, any typed pointer, `string` | 4 | 8 |
| `NativeInt`, `PtrInt`, `PtrUInt` | 4 | 8 |

`Real` is the one scalar whose width is a *target* decision rather than a
pointer-width one — 8 on the desktop targets and 4 on the ESP class. It has its
own section under [Types](../language/types.md#real-is-the-targets-native-float),
including why, and it is the reason not to name `Real` in anything shared with
another program.

## Strings

### `string` is a handle, not the characters

`SizeOf(string)` is the pointer width — 8 on a 64-bit target, 4 on a 32-bit one
— because the variable holds a reference to a managed, reference-counted,
heap-allocated buffer. **It is not the length of the text and it is not a
bound on it.** A `record` containing a `string` field is likewise 8 bytes wider
per field, not "wide enough for the text", so a record with a `string` in it
cannot be blitted to a file: writing the handle writes a pointer into a heap
the reader does not have.

This is worth stating plainly because FPC's answer depends on its mode. Under
`{$mode delphi}` or `{$H+}` FPC agrees with us and `SizeOf(string)` is the
pointer width; in FPC's own default mode a plain `string` is a 256-byte
shortstring instead. **PXX has one `string` and it is always the managed one.**

### `string[N]` is fixed-width and blittable

A capacity-bounded string is a length prefix followed by the characters, laid
out inline. This is the type to use when a width has to be known — a record
written to a flat file, a fixed field in a wire format.

| Declaration | Size, all targets | Layout |
| --- | --- | --- |
| `string[1]` | 2 | 1-byte length + 1 char |
| `string[10]` | 11 | 1-byte length + 10 chars |
| `string[255]` | 256 | 1-byte length + 255 chars |

**Guaranteed for `N` from 1 to 255: `SizeOf(string[N])` is `N+1`, on every
target, and it is byte-for-byte what FPC produces.** So a file of fixed strings
written by PXX is readable by an FPC program and the reverse, and a 32-bit and
a 64-bit build of the same PXX program agree.

**`N` above 255 is a PXX extension, and it does not have the same guarantee.**
FPC refuses the declaration outright — *"string length must be a value from 1 to
255"* — so there is nothing to be compatible with, and PXX switches to an
8-byte length word to hold the larger count:

| Declaration | 32-bit targets | 64-bit targets |
| --- | --- | --- |
| `string[256]` | 264 | 264 |
| `string[300]` | **308** | **312** |
| `string[1000]` | 1008 | 1008 |

The size is `N+8` rounded up to the target's pointer alignment, which is why
`string[300]` differs between word sizes while `string[256]` does not.
**Do not put a `string[N>255]` in a record you write to a file that a
differently-sized build will read.** For a portable fixed field, stay at 255 or
below, or use an `array[1..N] of Char` and carry the length yourself.

The trailing padding is *incidental*: the rule (8-byte count, then align) is the
contract; that `string[300]` happens to land on 312 rather than 316 is not.

## Sets

**A set is 32 bytes on every target, always, whatever its declared bounds.**
Guaranteed.

```pascal
type
  TSmall = set of 0..7;      { SizeOf = 32 }
  TBytes = set of Byte;      { SizeOf = 32 }
  TChars = set of Char;      { SizeOf = 32 }
  TFlags = set of (fA, fB);  { SizeOf = 32 }
```

The width does **not** follow the declared bounds. That is a deliberate choice
and not a pending optimisation: one width means a set never changes size when
its element type gains a member, and the RTL needs no per-set-size code paths.

The layout is a plain bitset — ordinal *n* is bit `n mod 8` of byte `n div 8`,
so ordinals 0..255 all fit and nothing beyond 255 can be a set element.

**Our bytes are a zero-extension of FPC's.** FPC sizes a small set down to 1, 2
or 4 bytes (and how far depends on its mode: `set of 0..7` is 4 bytes under
`{$mode objfpc}` and 1 byte under `{$mode delphi}`). Where FPC's set is
narrower, its bytes are exactly our leading bytes. Measured: `[1, 3, 7]` is
`138` in byte 0 with every remaining byte zero under PXX, `138 0 0 0` under FPC
objfpc, and `138` under FPC delphi. So the low bytes of a PXX set can be read
directly by FPC code that knows the narrower width — but a PXX set written whole
is 32 bytes and an FPC reader must expect that.

## Records

**Field offsets and padding match FPC exactly.** Guaranteed, and measured
identical on all five runnable targets:

```pascal
type
  TRec  = record B: Byte; L: LongInt; end;          { SizeOf 8, L at offset 4 }
  TPack = packed record B: Byte; L: LongInt; end;   { SizeOf 5, L at offset 1 }
```

An unpacked record aligns each field to its own size and pads the whole record
to its widest member. `packed` removes all of it. There is no PXX-specific
alignment rule to learn: if you know FPC's layout, you know ours.

The two caveats are about what is *inside* the record, not the record: a field
of a managed type (`string`, a dynamic array, an interface) is a pointer, and a
`string[N>255]` field carries the word-size dependence described above. A record
of scalars, fixed strings up to 255, and other such records is blittable.

## `file of T` and `BlockWrite`

A typed file writes exactly `SizeOf(T)` per record and the cursor advances by
the same, so element *k* is at byte offset `k * SizeOf(T)`. Measured, writing
two records each:

| Declaration | Bytes per record |
| --- | --- |
| `file of Char` | 1 |
| `file of LongInt` | 4 |
| `file of packed record B: Byte; L: LongInt; end` | 5 |
| `file of record B: Byte; L: LongInt; end` | 8 |

`BlockWrite` on an untyped `file` writes exactly the count you pass, and
`SizeOf(v)` is the right count for a blittable `v` — verified for a
`string[10]` (11 bytes) and a `string[300]` (312 on a 64-bit target).

**One current limitation:** `file of string[N]` does not compile. `Write` to one
is refused with a width that disagrees with `SizeOf`, even though the element
size the file records is correct. FPC compiles the same program. Until it is
fixed, write fixed strings through `BlockWrite` on an untyped file, or wrap the
string in a record. This is tracked in the project backlog; it is a defect in
one argument-size path and not a property of the layout, which is why the
`string[N]` rows above are still the contract.

## What PXX deliberately does differently from FPC

Everything else on this page is FPC's layout. These three are chosen:

| | PXX | FPC | Why |
| --- | --- | --- | --- |
| `SizeOf(set)` | always 32 | 1–32, follows the bounds and the mode | one width, no per-size RTL paths; our bytes zero-extend theirs |
| `SizeOf(string)` | always the pointer width | pointer width in Delphi/`{$H+}` mode, 256 in FPC's default mode | PXX has one `string` and it is managed |
| `string[N]`, `N > 255` | accepted, 8-byte count | rejected outright | a capability FPC does not offer; the cost is the word-size dependence noted above |

None of these is a gap waiting to be closed.

## Check it yourself

The whole contract fits in one program. Compile and run it on any target you
care about rather than trusting the tables above:

```pascal
program contract;
type
  S10   = string[10];
  S255  = string[255];
  TSet  = set of Byte;
  TRec  = record B: Byte; L: LongInt; end;
  TPack = packed record B: Byte; L: LongInt; end;
var
  r: TRec;
  a: array[0..1] of S10;
begin
  writeln('Pointer      ', SizeOf(Pointer));
  writeln('string       ', SizeOf(string));
  writeln('string[10]   ', SizeOf(S10), '  stride ', SizeOf(a) div 2);
  writeln('string[255]  ', SizeOf(S255));
  writeln('set of Byte  ', SizeOf(TSet));
  writeln('record       ', SizeOf(TRec), '  L at ', PtrUInt(@r.L) - PtrUInt(@r));
  writeln('packed       ', SizeOf(TPack));
end.
```

On a 64-bit target, and on a 32-bit one for comparison:

```
                 x86-64   i386
Pointer            8        4
string             8        4
string[10]        11       11    stride 11 on both
string[255]      256      256
set of Byte       32       32
record             8        8    L at 4 on both
packed             5        5
```

**Two rows move and five do not.** That is the shape of the whole contract: the
pointer-width rows follow the machine and everything else is fixed. Cross-compile
it with `--target=i386` (or `arm32`, `riscv32`, `aarch64`) and run it under qemu
to reproduce the right-hand column.

## What these numbers were measured with

Every size, stride, offset and file width on this page was produced by running
a probe program, not by reading the compiler source.

- **Compiler:** PXX at commit `ce19e5482`, binary SHA-256 `9bcfd2b4da30…`.
- **Targets:** x86-64 natively; i386, arm32, riscv32 and aarch64 under qemu.
  Every row marked "all targets" was run on all five. The xtensa and wasm32
  targets were not run.
- **FPC comparisons:** Free Pascal 3.2.2 for x86-64, with the mode named in the
  row, since several of its answers are mode-dependent.

The `string[N > 255]` word-size dependence is the reason the target list
matters: on x86-64 alone, `string[300]` measures 312 and looks like a constant.

## Next

- [Types](../language/types.md) — the language-level tour of the same types
- [FPC compatibility](../language/fpc-compatibility.md)
- [Current limits](./limits.md)
