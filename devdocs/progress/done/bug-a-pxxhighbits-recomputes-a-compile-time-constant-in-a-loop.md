---
track: A
prio: 50
type: bug
blocked-by: []
status: done
owner: frankS
found: 2026-08-30
found-by: frank-optimize, profiling bug-o-uforth-blocktest-runs-slower-under-pxx-than-under-cpython
summary: "FIXED 2026-08-31 (467b66a44). Now a const keyed on CPU64/CPU32, byte-identical to what the loop produced on each width. Measured on the workload the profile came from: uforth tests/core.fr 2.67s -> 2.51s, 6.0% against the profile's predicted 5.1%; a concat microbench 24%. NOTE the original summary's mechanism was WRONG -- the call sits OUTSIDE PXXBlockCopy's word loop, once per copy, not once per machine word. The measured cost was right; the story about where it came from was not."
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


## 2026-08-31 — FIXED, and the mechanism in the summary was false

`467b66a44`. `PXXHighBits` is gone; the mask is a const:

```pascal
const
{$ifdef CPU64}
  PXX_HIGH_BITS = Int64($8080808080808080);
{$else}
  PXX_HIGH_BITS = Int64($80808080);
{$endif}
```

Keyed on `CPU64`/`CPU32`, which `lexer.inc` predefines for every target,
**not** on a list of target names — the enumeration is the part that goes stale,
and a mask one word too wide is a silently wrong ASCII verdict rather than a
build error. Both values are byte-identical to what the loop produced at that
width, so this is a pure cost change.

### The ticket's own mechanism was wrong, and it matters

> "called once per machine word of every string ASCII scan"

It is not. The call sits **outside** `PXXBlockCopy`'s word loop:

```pascal
  if PXXWordCopyOk(d, s, n) then
    while i + w <= n do ...            { the word loop -- no call in it }
  if (acc and PXXHighBits) <> 0 then ...   { HERE: once per PXXBlockCopy }
```

So it is once per **copy**, not once per word. The measured 5.1% was right
anyway, because uforth's copies are short — a 26-byte string is three words, and
an eight-iteration loop through memory dwarfs it. But the numbers and the story
were separable, and only the numbers survived.

### Why a const rather than the compiler folding it

Option 3 in the original write-up was a general constant-fold, "worth a grep for
siblings before choosing, since the general fix is only worth it if there are
several." The grep says there are not: the whole tree contains **two**
parameterless constant-returning helpers, and the other one, `PXXWordStep`, has
**zero callers** — it is dead. A population of one hot site does not justify a
folding pass, which under the O-charter would need promise and Track T proof of
its own. (`PXXWordStep`'s deadness is noted, not acted on: deleting code you
believe is dead is not a just-fix-it, and it is not this ticket.)

For the record on what the compiler does and does not fold: `SizeOf(NativeInt)`
IS folded (it reaches the IR as `const_int ival=8`), and `SizeOf(NativeInt) - 1`
is NOT — it reaches the IR as a runtime `binop`. The *const section* evaluator
folds the full expression, which is why the const form costs nothing while an
inline expression at the call site would not have.

### Measurement, one variable

Builtins are read from disk at user-compile time, so the before/after binaries
were produced by the **same compiler binary** with only `builtinheap.pas`
swapped (via a stash, not a copy). Interleaved, min of 5:

| workload | before | after | |
| --- | ---: | ---: | ---: |
| uforth `tests/core.fr` — the workload the profile came from | 2.67s | 2.51s | **6.0%** |
| 2M string concats | 0.33s | 0.25s | **24%** |

uforth's output is byte-identical across the two, 24 lines. The 6.0% against a
profile that predicted 5.1% is the closest agreement between a sampled profile
and a delivered number I have measured here.

The ticket asked to "re-run the sampled profile and confirm the routine leaves
the top 20". It leaves it by not existing, which is a stronger statement than
the profile could have given — so the profile was not re-run.

### Positive control, because a probe that cannot fail proves nothing

With `PXX_HIGH_BITS` set to `Int64(0)` and nothing else changed, a NilPy `len()`
over a concatenated non-ASCII string reports **24** (bytes) instead of **20**
(codepoints) — the ASCII flag is wrongly set and `len()` stops counting UTF-8.
So the probe below is capable of failing:

```
x86-64   len_c=20   matches the CPython oracle exactly
arm32    len_c=20   matches the CPython oracle exactly   <- this is what covers CPU32
i386 / arm32 / aarch64 / native   Pascal concat byte-exact, len=24 bad=0
```

**i386 cannot run the NilPy probe at all** — `builtin/pyeval.pas` fails to parse
for that target under the **pinned** compiler too, so it is pre-existing and
outside this change. `arm32` is therefore the evidence for the 32-bit arm, and
it is real evidence rather than a substitute: the const is selected by `CPU32`,
which both targets define.

`gate.sh quick` GREEN at `5a256db106c5`.

## Log
- 2026-08-31 — resolved, commit PENDING-COMMIT.
