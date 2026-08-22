---
slug: bug-a-absolute-cannot-overlay-an-untyped-var-parameter
track: A
prio: 30
type: bug
status: backlog
blocked-by: []
summary: "`procedure Zap(var x); var b: array[0..255] of Byte absolute x;` is refused with 'absolute: target must not be a by-reference parameter'. That IS the idiom untyped parameters exist for — FPC compiles it — and the overlay machinery cannot express it because it works by copying the target's Offset, which for a by-ref param aliases the POINTER rather than the pointee."
---

# `absolute` over an untyped `var` parameter is refused

```pascal
procedure Zap(var x; n: Integer);
var b: array[0..255] of Byte absolute x;
    i: Integer;
begin for i := 0 to n - 1 do b[i] := 0; end;
```

```
error: absolute: target must not be a by-reference parameter
```

FPC compiles it. This is not an exotic corner: an **untyped `var` parameter has
no other way to be read**. You get a name with no type, and the two ways to give
it one are a hard cast (`PByte(@x)`) and `absolute`. Turbo Pascal, Delphi and
FPC code all use the second, so any source doing bit-level work over an untyped
buffer hits this at its first routine.

## Why the check exists, and why it is not simply wrong

The overlay is implemented by giving the new symbol the target's storage:

```pascal
if (absTarget >= 0) and (not isDyn) then Syms[idx].Offset := Syms[absTarget].Offset;
```

For a local, a global or a by-value parameter that is exactly right. For a
**by-ref** parameter the slot holds the ADDRESS of the caller's variable, so
copying the Offset would overlay the POINTER — eight bytes of address read as
the user's data. That is a silent wrong value, and refusing it loudly was the
correct call at the time. The check is doing its job; what is missing is the
representation that would let the overlay say "the storage is *at* this slot's
contents".

## Shape of the fix

The compiler already grew exactly this distinction elsewhere today, twice:
`IRDynHandleSlotAddr` (`compiler/ir.inc`) answers "where does this thing's
storage actually live" as `IR_SLOTADDR`, plus an `IR_LOAD_MEM` when the symbol
is a by-ref param. An `absolute` overlay onto a by-ref target needs the same
one-bit distinction on the SYMBOL rather than in one lowering:

1. A `SymAbsoluteViaPtr[idx]` flag (or an `AbsTarget` field, which the symbol
   table does not have today — the overlay is currently *lossless only because*
   it collapses into an Offset).
2. Every read/write of such a symbol derefs the slot first. That is one place if
   the flag is consulted in `IRLowerAddress` / the ident load, and six places if
   it is done per backend — the first is the only acceptable answer.
3. `SizeOf`, `@`, and passing the overlay onward must all go through the same
   path, which is the part that makes this a real ticket and not a patch: the
   current overlay is invisible after declaration, and this one would not be.

## Related, and why this is filed at 30 rather than higher

Failure mode is a **loud compile error**, so no program silently misbehaves —
the cost is source that will not build, not a wrong answer. Adjacent work landed
2026-08-22: `bug-a-an-absolute-array-overlay-is-silently-ignored` (a fixed array
may now overlay; a dynamic one is refused by name). This ticket is the remaining
refusal in the same feature, and the only one that blocks an idiom with no
alternative spelling other than a cast.

Found by the parameter-passing differential family.

## Gate

Track A's, plus the routine above zeroing a caller's Integer and a caller's
record, and a row proving a `const` untyped parameter (`const x`) reads
correctly through the same overlay.
