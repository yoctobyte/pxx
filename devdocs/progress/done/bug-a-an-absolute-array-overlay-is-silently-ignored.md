---
slug: bug-a-an-absolute-array-overlay-is-silently-ignored
track: A
prio: 60
status: done
commit: 35ef86078
---

# `array ... absolute x` is accepted, aliases nothing, and says nothing

```pascal
var i: Integer;
    b: array[0..3] of Byte absolute i;
begin
  i := $04030201;
  WriteLn(b[0], ' ', b[1], ' ', b[2], ' ', b[3]);   { fpc: 1 2 3 4   pxx: 0 0 0 0 }
  b[0] := 9;
  WriteLn(i);                                        { fpc: ...09     pxx: unchanged }
end.
```

The byte-view overlay is the single most common use of `absolute` in real
Pascal, and it was the one shape the feature did not implement. Reads returned
0, writes went to a slot nobody else could see, and **nothing was reported** —
the declaration compiled clean.

## Why it was excluded, and why the exclusion was wrong

The overlay is one line — give the new symbol the target's offset instead of
its own — and it was guarded:

```pascal
{ ... Arrays never carried an overlay and still do not. }
if (absTarget >= 0) and (not isArr) then Syms[idx].Offset := Syms[absTarget].Offset;
```

`not isArr` was doing two jobs at once. A **dynamic** array genuinely cannot
overlay anything: its slot holds a heap handle, so aliasing it would reinterpret
the target's bytes as a pointer and eventually free them. A **fixed** array has
exactly the property the overlay needs — `Offset` is the base of its contiguous
storage — so it aliases by the same one line as a record does, and a record
overlay already worked.

So the guard is now `not isDyn`, and the dynamic case is **refused loudly** at
the declaration:

```
error: absolute: a dynamic array cannot overlay a variable
```

That is the real defect this ticket is about. The feature already rejects five
other bad overlays by name (a constant target, a by-ref parameter, a local over
a global, a global over a local, a missing name) — every one of them an `Error`.
The array case took the *silent* branch instead, which is the one outcome the
surrounding code had deliberately avoided everywhere else. A limitation you
announce costs a user a minute; a limitation that answers 0 costs a debugging
session.

## Verification

`test/test_absolute_array_overlay.pas`, byte-identical to
`fpc 3.2.2 -Mobjfpc -O1`:

```
glob 1 2 3 4 5 6 7 8          array over a global Int64
rec 513 1027                  record overlay — the control, always worked
write 578437695752307299      a write through the array reaches the target
view 1 2 3 4 5 6 7 8          array over an ARRAY (Word[4] seen as Byte[8])
local 1 2 3 4                 array over a routine local
words 513 1027                two different element widths over one slot
back -16580095                a write through the local view
```

Both scope classes, both directions of the write, and two element widths over
one storage, because the failure mode was "the alias never happened" and a
read-only test cannot tell that apart from a lucky zero.

Found by the type-conversion/cast differential family, not by a ticket.

Gate: `make compiler/pascal26` (fixedpoint, converged after 1 round) +
`tools/gate.sh quick` GREEN.
