---
track: A
prio: 55
type: bug
blocked-by: []
found: 2026-09-02
found-by: frankB
owner: —
summary: "`@a[0]` inside a callee does NOT equal the caller's `@arr[0]` for an open-array parameter, on EVERY element type (LongInt, record, string[10]) and for `var`, `const` and value alike -- FPC answers TRUE for all of them. Found as the control while fixing bug-p-a-string-n-element-loses-its-capacity-in-three-container-shapes, and it is NOT that bug: element ACCESS and WRITE-THROUGH are correct (`a[2]` reads the caller's value and `a[2] := x` propagates), so only the address-of path diverges. Cause is the copy-in/copy-out marshalling documented at `ir.inc`'s static-to-open-array arms: pxx materialises a `[len:8][data]` temp and passes it, which the comments there call 'observably equal to true aliasing unless the callee reaches the same array by another path during the call' -- `@` IS that other path, so the stated exception is reachable from one operator. LOW-ISH PRIO BECAUSE IT IS NOT A WRONG VALUE: the address is a valid, writable, correctly-strided view whose writes are copied back, so a callee that only indexes is unaffected. It bites when an address ESCAPES: stored past the call, compared against a caller address, or passed to a routine that outlives the frame. Worth filing rather than fixing inside a p100 because the honest fix is real aliasing for `var`, not a patch to `@`."
---

# `@a[i]` on an open-array parameter addresses the marshalling temp, not the caller's array

## Measured, 2026-09-02, binary `a0fbf36e29f4`

```pascal
var gi: array[0..3] of LongInt;  b: PtrUInt;
procedure Pi(var a: array of LongInt);
begin WriteLn(PtrUInt(@a[0]) = b); a[2] := 99; end;
...
b := PtrUInt(@gi[0]); Pi(gi); WriteLn(gi[2]);
```

|  | pxx | fpc |
| --- | --- | --- |
| `@a[0] = @gi[0]` | **FALSE** | TRUE |
| `a[2]` read | 2 (correct) | 2 |
| `gi[2]` after `a[2] := 99` | 99 (correct) | 99 |

Same three rows for `array of TR` (a record) and `array of string[10]`, and the
same for `const` and value parameters. **It is not element-type-specific** —
that is what separates it from the capacity family, where LongInt and record
were correct and only the frozen string was wrong.

## Why the write still propagates

`ir.inc`'s var/out open-array arm copies the static array into a header'd temp
and registers a copy-OUT after the call. Its own comment states the limit:

> copy-in / copy-out aliasing — observably equal to true aliasing **unless the
> callee reaches the same array by another path during the call**

`@` is that other path, and it needs no second path *into* the array — taking
the element's address and comparing or storing it is enough. So this is a
DOCUMENTED exception that turns out to be reachable from a single operator,
rather than an unknown divergence. Recording it means the next person meets a
ticket instead of re-deriving it from the comment.

## What it does and does not break

**Does not:** indexing, `Length`/`High`, reading, writing, writeback. A callee
that treats the parameter as an array is correct throughout — which is why this
survived: the temp is a faithful, correctly-strided, writable copy.

**Does:** any address that OUTLIVES or ESCAPES the call — stored into a
structure that outlives the frame, compared against a caller-side address (the
row above), or handed to a routine that keeps it. Also anything relying on the
callee and caller observing each other's writes *during* the call.

## The fix is aliasing, not a patch to `@`

Making `@a[i]` return the caller's address while the callee still indexes a temp
would be worse than the current state: the two would disagree. For a `var` open
array the correct answer is to pass the caller's array directly. The reason a
temp exists at all is the `[len:8]` header that `High`/`Length` read — a static
array has none — so the real fix is a way to carry the length beside a borrowed
pointer rather than by prefixing a copy.

**Do not fix this inside the byte-prefix feature.** It is unrelated to the
prefix width and would confuse attribution there.

## Gate

`make test` + self-host + cross. Assert `@a[0] = @caller[0]` AND that indexing
still works — the second is what a naive fix breaks.
