---
track: A
prio: 50
type: bug
blocked-by: []
status: working
owner: frankS
found: 2026-08-30
found-by: frank-optimize, profiling bug-o-uforth-blocktest-runs-slower-under-pxx-than-under-cpython
summary: "PXXHighBits builds the constant $8080808080808080 with an eight-iteration shift/or loop, and is called once per machine word of every string ASCII scan. A gdb-sampled profile of uforth put 5.1% of the program's ENTIRE runtime inside it — the fifth-hottest routine in a 134-routine profile, spent recomputing a value the compiler could fold."
---

# `PXXHighBits` recomputes a compile-time constant in a loop

`compiler/builtin/builtinheap.pas:1608`:

```pascal
function PXXHighBits: Int64;
var i, m: Int64;
begin
  m := 0;
  for i := 0 to SizeOf(NativeInt) - 1 do
    m := (m shl 8) or $80;
  PXXHighBits := m;
end;
```

Eight iterations of shift-or to produce `$8080808080808080`. It is called from
the ASCII high-bit test at `builtinheap.pas:1633`:

```pascal
if (acc and PXXHighBits) <> 0 then acc := $80 else acc := 0;
```

— i.e. **once per machine word of every string scanned**.

## Measured

gdb-sampled profile of pxx-compiled `uforth` (`-g`, `handle SIGINT stop nopass`,
`$pc` bucketed by call-target entry), 593 samples across five ANS word sets,
compiler at `0604b414089f`, binary `883476f0abaf`:

| samples | % of total | routine |
| ---: | ---: | --- |
| 73 | 12.3% | allocator entry |
| 45 | 7.6% | free path |
| 36 | 6.1% | string size/offset |
| 30 | 5.1% | block/ASCII copy |
| **30** | **5.1%** | **`PXXHighBits`** |

Identified from the disassembly by its shape — a loop over 0..7 doing
`acc = (acc shl 8) or $80` — before the source was located, so the
identification is independent of reading the Pascal.

For scale: the whole compiled body of `uforth.py` accounts for 4% of samples.
**This one constant costs more than all of the user's code.**

## The fix, and the reason it is not simply "write the literal"

Writing `$8080808080808080` directly is wrong on a 32-bit target, which is why
the loop is keyed on `SizeOf(NativeInt)` and why it was written this way. Three
options, in increasing order of value:

1. **Cache it** in a unit-level variable initialised once. Smallest change,
   removes ~5% here, keeps the 32-bit correctness. Not free — a global read per
   call, and the unit needs an init path.
2. **`const` per target width**, selected by `{$IF SizeOf(NativeInt) = 8}` or the
   equivalent the RTL already uses elsewhere. Zero runtime cost, no init order
   question. Most likely the right answer.
3. **Constant-fold it in the compiler** — a parameterless function over
   compile-time-known values is foldable, and this is unlikely to be the only
   instance. Strictly the best fix and strictly the largest; worth a grep for
   siblings before choosing, since the general fix is only worth it if there are
   several.

Recommend **2**, plus the grep that decides whether 3 is worth filing.

## Verification

The repro is any string-heavy NilPy or Pascal program; `uforth` on
`coreexttest.fth` is the one measured. Re-run the sampled profile and confirm
the routine leaves the top 20. A wall-clock A/B on a short word set should show
~5%, which is at the edge of this box's noise — so the profile, not the clock,
is the instrument that settles it.

## Gate

`make compiler/pascal26` + `gate.sh quick`. Touches the RTL that every program
links, and the 32-bit inline tier is exactly what the loop exists to get right,
so the i386 and arm32 targets are the ones to check, not just x86-64.
