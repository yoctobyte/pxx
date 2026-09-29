---
track: A
prio: 10
type: bug
blocked-by: []
status: done
found-by: frankH (while making StringOfChar reachable without uses), via frankuser
tags: [pascal, shortstring, frozen-string, memory-corruption, setlength]
summary: "SetLength on a frozen string (a ShortString, a string[N], and every string under -uPXX_MANAGED_STRING) stored its count into the length prefix unclamped. A ShortString kept the count's low byte (SetLength(s, 1000) read back 232, 400 read back 144), a string[10] took 50, and a loop over Length(s) then wrote past the buffer: SIGSEGV, or a silently overwritten neighbour. This hit DEFAULT builds on every target, not only -u mode, through any declared ShortString or string[N]. HexStr/OctStr/BinStr and SetString also looped to their own count rather than the length they got. The parser now clamps the count to 0..N (a literal folded; anything else evaluated once into a hidden temp and clamped INLINE, since the first version's builtin helper was invisible to a program that doesn't load builtin, and silently skipped the clamp there), and those four builtin loops run to Length. fpc clamps a ShortString at 255 and does NOT clamp string[N] at N (it overruns); pxx clamps both, a recorded divergence."
owner: ""
---

# SetLength on a ShortString does not clamp at its capacity

```pascal
var s: ShortString; t: string[10]; i: Integer;
SetLength(s, 1000);   { pxx: Length 232, fpc: 255 }
SetLength(t, 50);     { pxx: 50, fpc: 50 too; filling t overran it in both }
for i := 1 to Length(t) do t[i] := 'x';   { pxx: SIGSEGV }
```

No target or profile builds with frozen strings by default:
PXX_MANAGED_STRING is defined unconditionally (paslexer.inc) and `-u` is
opt-in. But a declared ShortString or string[N] is frozen in every build, so
the bug reached default programs on all six targets.

## Fix

- The parser's SetLength (pasparser_stmt.inc, ClampFrozenSetLenCount) clamps
  the count for a frozen-string target (the -101 arm) to 0..N. FrozenSetLenCap
  asks the capacity by shape, as the truncating assignment does: symbol, record
  field, array element, `p^`; 255 when there is no N. A literal count is
  folded. Anything else is assigned once to a hidden Integer temp, followed by
  `if tmp > N then tmp := N; if tmp < 0 then tmp := 0`, and SetLength takes the
  temp, so `SetLength(s, f())` still calls f once. All seven backends' -101
  lowerings are untouched.
- builtin's HexStr, OctStr, BinStr and SetString looped to their own count
  after SetLength. They now loop to the length SetLength produced, which is
  what made `HexStr(1, 300)` crash under -u.
- StringOfChar (builtin) goes back to SetLength plus a fill to Length, which
  is linear, instead of the concatenation it used only because SetLength did
  not clamp.

The other growers were measured and already stayed inside the buffer: Insert,
concatenation, IntToHex with a wide width, and Str with a width, into a
ShortString and into a string[10].

## Divergence from fpc

fpc 3.2.2 clamps only at 255. `SetLength` on a string[10] to 50 reads back 50,
and a fill overruns the variable. pxx clamps at N, recorded in
devdocs/dev/pascal-dialect-divergences.md. A negative count gives 0 in pxx;
fpc keeps its low byte (-1 gives 255, -5 gives 251).

## Tests

- test_setlength_on_a_shortstring_clamps_at_255: the rows fpc defines (literal
  and variable counts, a count evaluated once, a var ShortString parameter,
  Insert, concatenation, IntToHex, Str with a width), each filling to Length
  with a guard beside it. Expected output is fpc 3.2.2's; it passes on six
  targets. The pushed compiler (f499d25ded) prints 232/144/184 there.
- test_setlength_on_a_string_n_clamps_at_n: string[N] in all four shapes,
  negative counts, and HexStr/OctStr/BinStr at width 300. Expected output is
  pxx's (the divergence); it passes on six targets and under
  -uPXX_MANAGED_STRING on x86-64. The pushed compiler's output is overrun
  garbage.

## The first fix skipped itself (5ebf185c24), caught by frankd-90

The first version clamped a variable count through a builtin helper,
`PXXShortLenClamp`, and skipped the clamp when FindProc could not see it.
builtin is loaded into a program with no uses clause only when a pre-scan
trigger name appears. So frankd-90's `var t: string[10]; n := 50;
SetLength(t, n)` plus a fill still segfaulted on the tip, a negative variable
count still gave 251, and `p^` of a ShortString still crashed. Adding a
`HexStr` call anywhere made it pass, and both fixtures above called HexStr (or
IntToHex through SysUtils), so they were green for the wrong reason. The
clamp is now inline and needs nothing loaded.

- test_setlength_clamps_with_no_builtin_in_the_program: no uses clause and no
  builtin trigger names, and only variable or call counts (a literal is folded
  and would pass without the runtime clamp): string[N] variable, ShortString,
  negative variables, a record field, an array element, `p^` of a
  ShortString, a count evaluated once, a var parameter. It passes on six
  targets and under -uPXX_MANAGED_STRING on x86-64. NEGATIVE CONTROL: the
  pushed tip e0b85a7460 segfaults on it, printing 50/232/251 and an
  overwritten guard before it dies.

The same silent-skip shape exists at 37 other FindProc sites:
task-a-a-missing-runtime-helper-silently-skips-its-action-in-38-places.
