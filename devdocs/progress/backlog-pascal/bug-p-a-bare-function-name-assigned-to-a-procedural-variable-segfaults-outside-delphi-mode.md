---
track: P
prio: 60
type: bug
blocked-by: []
summary: "`f := G;` where `f` is a procedural variable and `G` a function compiles OUTSIDE `{$mode delphi}` and segfaults at runtime. FPC rejects it there (`Incompatible types: got LongInt`) and accepts it only in Delphi mode, which pxx also gets right — so the Delphi arm is correct and the DEFAULT arm is the defect. Silent accept plus a crash is the worst of the three possible answers; erroring like FPC is the fix."
---

# A bare function name assigned to a procedural variable segfaults outside Delphi mode

```pascal
program p;
type TF = function: Integer;
function G: Integer; begin G := 7; end;
var f: TF;
begin
  f := G;          { no @ — objfpc requires one }
  writeln(f());
end.
```

| | result |
|---|---|
| fpc 3.2.2 `-Mobjfpc` | `Error: Incompatible types: got "LongInt" expected "<procedure variable type of function:LongInt;Register>"` |
| fpc 3.2.2 `-Mdelphi` | prints `7` |
| **pxx, default mode** | **compiles `ok:`, then SIGSEGV (rc=139)** |
| pxx, `{$MODE DELPHI}` | prints `7` |
| pxx, default, `f := @G` | prints `7` |

Measured 2026-09-05 at `9bcfd2b4da30`, and identical under
`stable_linux_amd64/default/pinned`, so it is not new.

## Why the Delphi arm being right is the useful part

`DelphiMode` is documented in `defs.inc:2857` as relaxing exactly this — *"a bare
function name bound to a procedural-value target to take its address
(@F-optional) … this is the one behavioural delta"* — and it works. So the
machinery to bind the name to its address exists and is correct; what is missing
is the **rejection** on the other side of the flag. Outside Delphi mode the bare
`G` is being read as a CALL (FPC's reading — hence its `got "LongInt"`), the
Integer result is stored into a procedural slot, and `f()` then calls through 7.

## Why this is a bug and not a dialect choice

The compat ceiling asks what the source MEANT and prefers the answer that leaves
a mistake visible. Both readings of a bare `G` are defensible and FPC picks one
per mode; **neither of them is "store an Integer in a function pointer and jump
to it."** There is no mode in which this program is correct, so accepting it
silently is not latitude — the three available answers are error (FPC's, in this
mode), take-the-address (FPC's, in Delphi mode, which we already implement), and
crash, and we ship the third.

## Not mine to fix

Found by frankD (Track D, docs) while establishing what `{$mode delphi}` actually
changes, in order to write it down truthfully on `docs/reference/modes.md` —
which had claimed the mode markers *"do not switch PXX into a different semantic
mode"*. They do; this is one of the two deltas, and it is the one that crashes.

Filed rather than fixed: Track P frontend work, and frankB holds that topic.
