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

> **SUPERSEDED 2026-08-30 by the boundary measurement below.** The paragraph
> that follows read the split as "the `const`-array argument path specifically".
> That is **wrong**, and measurably so: by-value and open-array arguments fail
> too, so it is not about `const`. It is about which modes may form a COPY.
> Kept as written because it was the routing note whoever picked this up would
> have acted on, and a superseded guess is more useful visible than deleted.

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

---

## Boundary measured, 2026-08-30 (frankB — probes only, no fix)

24 probes at pin v393 (`1d69760deabe`), one program per cell so a crash cannot
mask a sibling. **The routing note above is wrong in a way that matters**, and
the corrected statement is narrower on one axis and wider on the other.

### It is not `const`. It is every mode that may COPY.

| mode | 2D array row `p[0]` |
| --- | --- |
| `const` | **SIGSEGV** |
| by value | **SIGSEGV** |
| `const g: array of Int64` (open array) | **SIGSEGV** |
| `var` | ok |
| `out` | ok |

`var` and `out` are the two modes that *must* pass an address. Every mode that
is free to hand the callee a copy fails. So the defect is not in the `const`
path; it is in forming the argument for a copying mode.

### It is not aggregate members. It is an array-typed ARRAY ELEMENT.

| container | `const` | `var` | by value |
| --- | --- | --- | --- |
| standalone `s: TG` | ok | ok | ok |
| record field `r.a` | ok | ok | ok |
| record field inside an array element `q[0].a` | **ok** | — | — |
| **array row `p[0]`** | **SIGSEGV** | ok | **SIGSEGV** |
| **array row through a record `r2.rows[0]`** | **SIGSEGV** | — | — |

Irrelevant, all measured: element type (`Int64` vs `Byte`), element count (4 vs
64), literal vs variable subscript, and `array[0..2] of TG` vs
`array[0..2, 0..3] of Int64`.

`q[0].a` is the control the routing note needed and did not have. It has an
array subscript in its access path, it is an aggregate member, it is passed
`const`, and it **works** — so "an array subscript anywhere in the path"
is not the trigger. What matters is that the *final* step yields an array-typed
value by subscripting. Its partner control is `r.a` by value: a copying mode
over an aggregate member, also fine.

### The mechanism, measured rather than guessed

`const` of a fixed array in pxx **does** pass a copy — the callee's `@g` is a
different, non-zero address from the caller's. That part works everywhere. What
breaks is the address the copy is made FROM:

```
standalone     @s          = 4301824    const arg addr = 4302184
record field   @r.a        = 4301856    const arg addr = 4302224
rec-in-array   @q[0].a     = 4302080    const arg addr = 4302264
array row      @p[0]       = 4301888    const arg addr = 0      <-- NULL
row via record @r2.rows[0] = 4301984    const arg addr = 0      <-- NULL
```

**The argument arrives as NULL, not as a wrong address.** `@p[0]` is correct at
the call site (4301888, and `@p[1]` is 4301880+32 as it should be) — the value
is lost between there and the callee.

And it faults on entry, not on extent: a callee that prints before touching the
parameter prints, then dies on the **first** element read.

```
before call
sum=  entered callee
  about to read g[0]
Segmentation fault
```

A callee that takes `@g` and never dereferences does not crash at all, which is
how the address table above was obtainable.

### An adjacent defect, offered as a lead and not a claim

The same shape one level deeper fails at COMPILE time instead, with a
diagnostic that is untrue:

```pascal
type TG = array[0..3] of Int64; TPa = array[0..2] of TG; TPb = array[0..1] of TPa;
var b: TPb;
  b[0][0][1] := 5;          { ok }
  x := PtrUInt(@b[0][0][1]) { ok — fully subscripted }
  x := PtrUInt(@b[0]);      { ok — one level }
  x := PtrUInt(@b[0][0]);   { error: wrong number of array subscripts }
  SumC(b[0][0]);            { same error — cannot even be called }
```

Triple subscripting itself is fine; what is rejected is forming a REFERENCE to a
partially-subscripted 3-level array. That is the same operation the 2D case gets
wrong, failing in a different way — so they may share a root, and a fix for one
is worth testing against the other. **Stated as a lead: two symptoms of one
operation is a hypothesis, not a measurement, and I did not read the lowering
code.** It is also why the 3D row could not be added to the tables above.

### What a fix must assert

Every cell of both tables, plus: the `q[0].a` and `r.a`-by-value controls stay
green (a fix that repairs the row by making every aggregate member take the
slow path would pass a test that only watches the failing cells), and the 3D
`@b[0][0]` diagnostic either goes away or is shown to be a separate bug.
