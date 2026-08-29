---
slug: bug-a-method-pointer-record-is-hard-sized-16-bytes-on-32-bit-targets
title: "A `procedure of object` is declared 16 bytes on every target, so SizeOf is wrong on all five 32-bit ones"
track: A
type: bug
prio: 20
status: backlog
found: 2026-08-28
found-by: frankwasm (fell out of falsifying the wasm32 IR_DEFAULT_MEM arm)
---

## The fact

```pascal
type TNotify = procedure of object;
     TM = record Code, Data: Pointer; end;
WriteLn(SizeOf(TM), ' ', SizeOf(TNotify));
```

| target | `record Code, Data: Pointer` | `procedure of object` | |
| --- | --- | --- | --- |
| x86-64 | 16 | 16 | correct |
| **i386** | **8** | **16** | wrong — measured by running |
| **arm32** | **8** | **16** | wrong — measured under qemu |
| **wasm32** | **8** | **16** | wrong — measured under node |
| riscv32, xtensa | — | — | same code path, not run |

A user-declared two-pointer record sizes correctly on a 32-bit target. The
built-in method-pointer record does not.

## Root cause

`compiler/symtab.inc`, `EnsureMethodPtrRec`:

```pascal
UClsSize_[ci]    := 16;
UClsAlign[ci]    := 8;
```

Both constants are the 64-bit values, minted once and used for every target.
The doc comment above them says *"the shared 16-byte method-pointer layout
{Code@0, Data@8}"*, which is a second copy of the same assumption in prose.

## What is NOT wrong, checked rather than assumed

**The layout is target-aware; only the declared size is not.** On i386 a real
method pointer read back through a `TM` cast returns the object in `Data` —
i.e. the store used offset 4, not the offset 8 the comment claims:

```
--- i386 ---
via cast: code<>0=TRUE data=obj=TRUE
hi
```

So this does **not** corrupt anything and does not misdirect a call. The temp is
allocated at the size the compiler believes, so the over-sized zeroing stays
inside its own allocation. What it costs is 8 wasted bytes per method-pointer
value on every 32-bit target, and a `SizeOf` that a program can read and that
disagrees with both the real layout and FPC.

prio 20 on that basis: observable, cheap to fix, harms nothing today. Please do
not read the low number as "not real" — it is measured, on three targets, by
running.

## Fix

Size and alignment from the target's pointer size rather than from a literal,
and correct the comment in the same edit — it states `Data@8` as fact and is
wrong on five of the seven targets. (`devdocs/dev/root-cause-over-microfix.md`
and the note that a deletion has copies too: the prose is the second copy here,
and the one that would survive a correct code fix.)

## How it surfaced, which is the part worth keeping

Falsifying the new wasm32 `IR_DEFAULT_MEM` arm. One break — halving the zeroed
byte count — did **not** turn the check red. The tempting reading was "the check
is weak". The real reason is this ticket: the record declares 16 bytes where the
32-bit payload is 8, so half of 16 still covers all of it. **A break that a check
cannot see and a break that changes nothing observable look identical from the
check's output**, and only chasing the second one turned up a real defect two
files away.

## What would raise this above p20

Added by the coordinator 2026-08-28, at the filer's request that the low number not
be read as "not real". The p20 is honest **today** because the cost is eight wasted
bytes per value on 32-bit and a `SizeOf` a program can read back wrong — no
corruption, and the store already uses the target's pointer size.

It stops being p20 the moment a **32-bit record layout has to match a binary this
compiler did not produce**: interop with an FPC-built unit, a serialized struct
read back by another toolchain, or any on-disk/on-wire format containing a
`procedure of object`. There, eight bytes of over-declaration is a field-offset
mismatch rather than waste. Nobody has hit that; if anyone does, this is not a p20
and the ticket should say so rather than being re-argued from scratch.
