---
prio: 45
track: A
type: bug
blocked-by: []
summary: "One arm of bug-aggregate-member-array-as-var-param (done) never got fixed: a ROW of a 2D array passed as a CONST array parameter still segfaults, on all five targets. The var form of the same row works, and the record-field form works in both modes, so three of the four cells that ticket's own acceptance named pass and the fourth does not. It is what still blocks reverting lib/rtl/ed25519.pas's 4-standalone-TGf workaround."
status: new
owner: ""
---

# A 2D-array row passed as a `const` array param still segfaults

- **Type:** bug (codegen — by-reference argument for an aggregate-member array)
  — **Track A**. Filed 2026-08-30 by frankB from Track B while working
  [[bug-b-seven-of-eight-workarounds-waiting-on-an-open-bug-are-waiting-on-nothing]].
- **Not a new bug.** It is the surviving arm of
  [[bug-aggregate-member-array-as-var-param]], which is in `done/`. Found by
  verifying that ticket **by behaviour** rather than by its folder, before
  reverting the workaround it justifies.

## The four cells, measured at pin v393 (`1d69760deabe`)

That ticket's own acceptance line names them: *"2D array row + array-typed
record field, var and const"*.

| container | param mode | result |
| --- | --- | --- |
| standalone `TG` | `const` | ok |
| record field `pr.a` | `var` | ok |
| record field `pr.a` | `const` | ok |
| **2D-array row `pa[0]`** | **`const`** | **SEGFAULT** |
| 2D-array row `pa[0]` | `var` | ok |

`SizeOf` is correct now — `TG=32 TPa=96 TPr=96` — so the element mis-sizing that
ticket diagnosed as the root **is** fixed. What survives is only the `const`
by-reference argument for an array ROW.

Repro:

```pascal
program agg3;
type TG = array[0..3] of Int64;
     TPa = array[0..2] of TG;
     TPr = record a, b, c: TG; end;
function SumC(const g: TG): Int64;
var i: Integer; begin SumC := 0; for i := 0 to 3 do SumC := SumC + g[i]; end;
var pa: TPa; pr: TPr; std: TG; i: Integer;
begin
  for i := 0 to 3 do begin std[i] := 1; pa[0][i] := 2; pr.a[i] := 3; end;
  writeln('standalone const : ', SumC(std),   ' (want 4)');
  writeln('record-field const: ', SumC(pr.a), ' (want 12)');
  writeln('array-row const  : ', SumC(pa[0]), ' (want 8)');   { SEGFAULT }
end.
```

```
x86-64   standalone 4, record-field 12, array-row  SIGSEGV
i386     standalone 4, record-field 12, array-row  SIGSEGV
arm32    standalone 4, record-field 12, array-row  SIGSEGV
riscv32  standalone 4, record-field 12, array-row  SIGSEGV
aarch64  standalone 4, record-field 12, array-row  SIGSEGV
```

Every target, so it is not a backend. The two working rows in each run are the
control: the same function, the same call, the same element type — only the
container and the mode differ.

## Why the `var`/`const` split is the interesting part

`var` on a row works and `const` on the same row does not, which points at the
`const`-array argument path specifically rather than at address-of for
aggregate members in general — that path is evidently right, because the `var`
row and both record-field forms take it correctly.

The likely shape is that `const` of a large array is allowed to pass a COPY (or
a pointer to a temp) where `var` must pass the address, and the copy path
mis-computes size or source for a row of a 2D array. That is a guess from the
boundary, not measured; whoever takes it should look at how `const <fixed-array>`
lowers its argument versus `var`.

## What it costs

It is what still blocks a workaround revert that otherwise looked ready:
`lib/rtl/ed25519.pas` models a point's four extended coordinates as **four
separate standalone `TGf` variables** rather than a `TPoint = array[0..3] of
TGf`, precisely because of the parent ticket. Its field ops take `const TGf`
(`AddF(var o: TGf; const a, b: TGf)` and eleven more), so the natural revert
passes `p[1]` as a `const TGf` — the exact failing cell. Shape-exact probe:

```pascal
type TGf = array[0..15] of Int64;
     TPoint = array[0..3] of TGf;
procedure AddF(var o: TGf; const a, b: TGf);
...
AddF(o, p[0], p[1]);      { SEGFAULT }
```

## What a fix must assert

- all five rows of the table above pass, on all five targets
- the same for a `const` row of a 3D array, and a row reached through a
  record field (`r.rows[0]`) — the neighbours of the failing cell
- a regression test covering the whole four-cell matrix, not one arm of it;
  the parent ticket's acceptance named the matrix and three quarters of it is
  what landed

## Independently confirmed by frank-coordinator, 2026-08-30, native x86-64

Reproduced with a probe written from the description rather than from frankB's
source — a second arm that does not share an upstream with the first (operating
rule 2's corollary: verify against a source the claimant did not choose).

```pascal
type TGf = array[0..15] of Int64;  TRows = array[0..1] of TGf;
procedure TakeVar  (var   a: TGf); begin Writeln('var   a[0]=', a[0], ' a[15]=', a[15]); end;
procedure TakeConst(const a: TGf); begin Writeln('const a[0]=', a[0], ' a[15]=', a[15]); end;
```

Built with the pinned binary:

```
SizeOf(TGf)=128 SizeOf(TRows)=256
var   a[0]=100 a[15]=115        <- the var cell WORKS
const a[0]=                     <- SIGSEGV, exit 139
```

Two details to add to the routing note:

- **`SizeOf` is correct (128 / 256)**, which corroborates that the element
  mis-sizing the original ticket diagnosed as root cause genuinely *is* fixed. This
  is a different defect that happened to live behind the same acceptance test.
- **The fault is on the FIRST element access inside the const procedure**, not on a
  later one — the literal `const a[0]=` is written, then it dies evaluating `a[0]`.
  So the parameter itself is bad on entry rather than the extent being wrong, which
  narrows it toward what the *caller* passes for a const aggregate member versus what
  it passes for a var one. `var` on the same row, same type, same call site shape,
  is fine.
