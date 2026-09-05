---
track: P
prio: 35
type: bug
status: done
found: 2026-09-01
found-by: claude-T
owner: frankA
blocked-by: []
summary: "FIXED. There is ONE token array -- main file, then each `uses`d unit, then the builtin units appended to every program, with nothing between them -- and the nine-token `near:` window had no idea, so it quoted across the seam and spliced the user's tokens onto ours. The window now clips at the anchor token's own source, the same way it already clipped at the ends of the array. Both repros in this ticket had gone stale; the replacement is three lines with no `end.`"
---

# A `near:` excerpt can quote an unrelated token stream

## Repro

```
tools/../compiler/pascal26 --strict-case --strict-operator \
  library_candidates/fpc-testsuite/tests/test/tgeneric50.pp /tmp/x50
```

```
pascal26:30: error: undefined variable (TTestInteger)
  near: ; interface type PVarRecInt64 = ^ >>> Int64 ; PVarRecDouble
```

Line 30 of `tgeneric50.pp` is `t := TTestInteger.Create;` — so the **line number
is right** and the **diagnosis is right**. The `near:` context is the problem:
`PVarRecInt64` / `PVarRecDouble` are RTL declarations that appear nowhere in
`tgeneric50.pp`.

For contrast, the same compiler on the same file family produces a correct
excerpt when it does not go wrong this way:

```
pascal26:14: error: expected 'begin' before 'deprecated'
  near: < T > = class end >>> deprecated 'Message A' ;
```

## Why this is worth a ticket rather than a shrug

`near:` exists to save the reader from opening the file. When it is right it is
load-bearing; the two agents who worked `tgeneric32`/`tgeneric49` on 2026-09-01
both used it. An excerpt that is confidently drawn from another file is worse
than no excerpt: it does not error, it is not obviously wrong, and it invites
reasoning about a construct that is not there.

Same class as the stale-stamp trap that `test-selfcompile-odiff` exists to
catch, and as the `pin-shadow` verdict being read as authority — an instrument
that answers a question other than the one asked, without saying so.

## Likely shape

The error path appears to index a token buffer that is not the one for the unit
under compile — probably the RTL/system unit's, left over or shared — while the
line number comes from the correct source position. Whoever takes it: the two
outputs above are enough to bracket it, since one file produces both a correct
and an incorrect excerpt depending on which error fires.

## Note

Found while triaging `regression-test-pascal-conformance-shard0-6-4`. Not
related to that regression's cause; the residual `tgeneric50` failure that
surfaces it is the specialization-alias hint-directive gap, which is separate
again.


---

## Repro REPLACED 2026-09-01 — the original one was fixed out from under it

The first repro used `tgeneric50.pp`, which **now compiles clean** (the
specialization-alias hint-directive gap was fixed the same evening). That file no
longer produces any error, so the original evidence is unreproducible.

**The defect itself is not stale — it still reproduces**, and the replacement is
smaller and a better bracket, because it pairs a correct excerpt with an
incorrect one from the same compiler in the same session.

### Control — excerpt is CORRECT

```pascal
program n1;
begin
  x := 1;
end.
```
```
pascal26:3: error: undefined variable (x)
  near: program n1 ; begin x >>> := 1 ;
```

### Repro — same error class, excerpt is from another token stream

```pascal
program n2;
{$mode delphi}
type
  TTest<T> = class end;
  TAlias = TTest<Integer>;
var
  t: TAlias;
begin
  t := TNotDeclared.Create;
end.
```
```
pascal26:9: error: undefined variable (TNotDeclared)
  near: ; end . unit builtinheap ; >>> interface type PVarRecInt64
```

Line 9 is right, the diagnosis is right, and `unit builtinheap` /
`PVarRecInt64` appear nowhere in the program.

### What the pair narrows it to

The difference between the two is that `n2` declares a **generic specialization
alias**. So the excerpt goes wrong only once the unit's token stream has been
extended by specialization minting: the position used for `near:` appears to
index past the end of the user's tokens and into the builtin/RTL stream, while
the line number is carried separately and stays correct.

That also explains why the original `tgeneric50.pp` sighting looked like a
generics bug and is not one — generics are how you *get* an extended token
stream, not what is broken. Any construct that appends tokens should reproduce
it.

### Note on staleness

Filed 2026-09-01 and already re-verified once the same day, because generics
were changing hourly. Anyone picking this up should re-run the pair first: the
control is the part that makes it a bracket rather than an anecdote.

---

## Resolution (2026-09-05, frankA)

**Both repros in this ticket were stale, and the mechanism they proposed was
wrong.** Re-run first, as the ticket asks: at `2422505f4` the `n1`/`n2` pair now
produces a CORRECT excerpt on both arms —

```
pascal26:9: error: undefined variable (TNotDeclared)
  near: TAlias ; begin t := TNotDeclared >>> . Create ;
```

So it is not generics, and it was never "the position indexes past the end of
the user's tokens while the line number is carried separately". The line number
and the anchor token were always the same token and both were always right.

### What it actually is

There is **one token array**, and every source goes in it: the main file first,
then each `uses`d unit, then the builtin units the compiler appends to every
program, with **nothing between them**. `WriteTokenContext` printed
`TokPos-6 .. TokPos+2` and clipped only at `1` and `TokCount` — the ends of the
ARRAY. It had no notion that the array holds several files, so a window centred
near a seam quoted two of them spliced together.

Live at `2422505f4`, three lines and no generics:

```pascal
program m1;
begin
  WriteLn('hi');
```
```
pascal26:2: error: a statement cannot start with 'unit'
  in: ./compiler/builtin/builtinheap.pas
  near: ( 'hi' ) ; unit builtinheap >>> ; interface type
```

`( 'hi' ) ;` is the user's and `unit builtinheap` is ours. That is the ticket's
observable exactly — *"an excerpt confidently drawn from another file"* — and it
reproduces without a generic anywhere near it. Any construct that runs the parse
off the end of the user's tokens gets there; generics were how the original
sighting got there, not what was broken.

### The fix

`WriteTokenContext` takes `PasSrcOfTok(TokPos - 1)` as the anchor's source and
skips any window token that does not answer the same. **This is the clip the
window already did, applied to what the array actually holds.** A shorter window
is the honest one:

```
  near: unit builtinheap >>> ; interface type
```

Deliberately not clever about which side to keep: a diagnostic whose anchor sits
in a builtin is truthfully about a builtin, and the `in:` note landed in
`310a8fa33` says whose file that is and which file to look at instead. The two
halves are one answer.

Frontends that plant no Pascal source ranges (C, NilPy) get `''` for every
token, so every token matches the anchor and their output is byte-identical —
`test_diag_near_window_nilpy_fail.npy` asserts an exact window and is unchanged,
as is the Pascal `test_diag_near_window_fail.pas` row.

### Fixture

`test/test_the_near_window_stops_at_the_file_boundary.pas`, asserted on the
WINDOW and not the exit code (the file has no `end.`, so it has always been
refused). Two rows, because the negative alone is a guard that cannot fail: one
asserts a `near:` line was printed AT ALL, the other that it does not carry
`'hi'` across the seam. Positive control: the pre-change binary prints the
spliced window above for exactly this source.

## Log
- 2026-09-05 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 7563532ad.
