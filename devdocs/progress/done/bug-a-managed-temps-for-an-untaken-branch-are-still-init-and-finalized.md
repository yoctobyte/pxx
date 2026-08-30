---
track: A
prio: 65
type: bug
blocked-by: []
status: done
owner: frankA
found: 2026-08-30
found-by: frank-optimize, profiling bug-o-uforth-blocktest-runs-slower-under-pxx-than-under-cpython
summary: "FIXED. A routine that merely MENTIONED a managed type in a branch it did not take paid that branch's temp finalization on every call. Two causes, each worth about half: (a) IRFlushPostCallIntf ran at the enclosing STATEMENT boundary, so a by-value record temp created inside an if-arm had its finalize emitted after the merge -- now flushed per arm; (b) the epilogue walked every managed record local through a heap-lock round trip even when the slot was all zero -- now branched over by a run-time all-zero test. Repro 20M calls, interleaved on one box: 9.77-10.52s -> 0.43-0.45s, against 0.27s for the hand-split form the workaround demanded. promocore.pas:796's rule -- keep every hot routine free of the managed type -- is retired rather than restated."
---

# Managed temps for an untaken branch are still init'd and finalized

## The isolated repro

Two functions, same semantics, same never-taken branch. The only difference is
whether the record type is named in the hot body or behind a call.

```pascal
type TBig = record neg: Boolean; limbs: array of Int64; end;

function SlowSplit(x, y: Int64): Int64;
begin SlowSplit := BTo(BAdd(BFromInt(x), BFromInt(y))); end;

function AddSplit(x, y: Int64): Int64;            { hot body names no TBig }
var r: Int64;
begin
  r := x + y;
  if ((x >= 0) = (y >= 0)) and ((r >= 0) <> (x >= 0)) then
    AddSplit := SlowSplit(x, y)
  else AddSplit := r;
end;

function AddInline(x, y: Int64): Int64;           { same, TBig named inline }
var r: Int64;
begin
  r := x + y;
  if ((x >= 0) = (y >= 0)) and ((r >= 0) <> (x >= 0)) then
    AddInline := BTo(BAdd(BFromInt(x), BFromInt(y)))
  else AddInline := r;
end;
```

20M calls each, `-O2`, x86-64, sha `0604b414089f`, box load 1.58 → 1.84 across
both halves:

| form | time | per call |
| --- | ---: | ---: |
| split — hot body free of `TBig` | **0.294 s** | 14.7 ns |
| inline — `TBig` named in the body | **13.060 s** | 653.0 ns |

**44x.** The branch is never taken in either.

### Re-measured at HEAD `3bc3b47ce326`, binary `faf762981c3c`, box load 4.20 -> 4.19

| form | time | per call |
| --- | ---: | ---: |
| split | **0.28 s** | 14.0 ns |
| inline | **13.14 / 13.27 s** | ~658 ns |

**47x — still there**, three shas and one pin later. Both halves back to back on
the same binary; the binary's sha256 was checked against the build's fixedpoint
line before the run, because the first attempt at this re-measurement was taken
on a throwaway experimental compiler still sitting in the tree and would have
been reported as a HEAD number.

### The repro, in full, so it cannot drift

It was previously cited as `$SCRATCH/uf/tbig.pas` — a session-local path that
outlives nothing. It needs no RTL beyond a dynamic array. Build with
`pascal26 -O2 tbig.pas tbig`, then run `tbig split` and `tbig inline`; each does
20M calls. It takes the arm as `ParamStr(1)` rather than timing both halves
in-process because there is no `GetTickCount64` here — time it with `time`, and
run the two halves back to back.

```pascal
program tbig;
{ Isolated repro of the mechanism: does merely MENTIONING a dynamic-array record
  in a never-taken branch cost the caller on every call? }
type
  TBig = record
    neg:   Boolean;
    limbs: array of Int64;
  end;
var
  i, n: Int64;
  acc: Int64;

function BFromInt(v: Int64): TBig;
begin
  SetLength(Result.limbs, 1);
  Result.limbs[0] := v;
  Result.neg := v < 0;
end;

function BAdd(const a, b: TBig): TBig;
begin
  SetLength(Result.limbs, 1);
  Result.limbs[0] := a.limbs[0] + b.limbs[0];
end;

function BTo(const a: TBig): Int64;
begin
  BTo := a.limbs[0];
end;

{ split form: the hot routine never names TBig }
function SlowSplit(x, y: Int64): Int64;
begin
  SlowSplit := BTo(BAdd(BFromInt(x), BFromInt(y)));
end;

function AddSplit(x, y: Int64): Int64;
var r: Int64;
begin
  r := x + y;
  if ((x >= 0) = (y >= 0)) and ((r >= 0) <> (x >= 0)) then
    AddSplit := SlowSplit(x, y)
  else
    AddSplit := r;
end;

{ inline form: identical semantics, but TBig is mentioned in this body }
function AddInline(x, y: Int64): Int64;
var r: Int64;
begin
  r := x + y;
  if ((x >= 0) = (y >= 0)) and ((r >= 0) <> (x >= 0)) then
    AddInline := BTo(BAdd(BFromInt(x), BFromInt(y)))
  else
    AddInline := r;
end;

begin
  n := 20000000;

  if ParamStr(1) = 'split' then begin
  acc := 0; i := 0;
  while i < n do begin acc := AddSplit(acc, 1); i := i + 1; end;

  writeln('split  -> ', acc); end else begin


  acc := 0; i := 0;
  while i < n do begin acc := AddInline(acc, 1); i := i + 1; end;

  writeln('inline -> ', acc); end;
end.
```

## What the emitted code does

`PXXPromoAdd`'s prologue before `0c3ad8a10`, from `objdump` of a `-g` build:

```
sub    $0x160,%rsp                 <- 352-byte frame for a 3-pointer routine
lea    -0x48(%rbp),%rdi ; xor %rax,%rax ; mov $0x10,%rcx ; rep stos %al,(%rdi)
lea    -0x58(%rbp),%rdi ; ...                                    (x21)
```

Two problems, and they are separable:

1. **21 managed temps are zeroed unconditionally**, for branches that the
   inline-tier fast path exits before reaching. The epilogue finalizes them
   again — 30 calls in the first 400 instructions.
2. **A 16-byte clear is emitted as `rep stosb`** (`rcx=0x10`, `stos %al`), i.e.
   byte at a time with microcode startup, where two `mov %rax` would do. This is
   worth fixing on its own and is much the smaller change.

## Why it matters beyond one file

`promocore.pas:796` has carried the diagnosis since the feature landed:

> A function that so much as mentions a TBig pays managed prologue/epilogue on
> EVERY call [...] Measured: with the slow path inline, one PXXPromoAddInt cost
> ~344 ns; split out, the fast path is a handful of instructions. **Keep every
> hot routine free of TBig.**

That is a correct diagnosis and a **workaround**: it was applied to
`PXXPromoAddInt`/`SubInt`/`MulInt` and to nothing else, so eleven sibling entry
points kept paying it for the entire life of the feature — `PXXPromoCmp`, the
one every Python `<` goes through, at 303 ns per call. `0c3ad8a10` hand-split
four more. `Mod`/`And`/`Or`/`Xor`/`Shl`/`Shr`/`ToStr`/`ToVariant` still have it.

This is the `normalise-dont-special-case` shape exactly: a rule that every
future author must remember, enforced by nothing, silently costing 20-40x when
forgotten. The codegen fix removes the rule.

## Suggested work

**Sink managed-temp init and finalization into the branch that uses them**, or
equivalently do not materialise a temp in a block the flow does not enter.
Fallback if that is too large: emit 16-byte clears as two stores rather than
`rep stosb`, which is independent and helps every managed frame.

Then delete the hand-splits in `promocore.pas` and re-measure — if the codegen
fix is real, `AddInline` and `AddSplit` converge and the `*Slow` routines become
unnecessary rather than mandatory.

## A second, independent witness for item 2 (2026-08-30, frank-optimize)

Item 2 — the 16-byte clear emitted as `rep stosb` — turns up again on the NilPy
side, reached from the opposite direction (profiling a Variant call, not a
managed record). Every NilPy `Variant` local is zeroed **three or four times**
in the same prologue, by three passes that do not know about each other:

| # | pass | emits, per Variant local |
| --- | --- | --- |
| 1 | `PyInitVariantLocals` (pyparser.inc:2074) | 2x `movq $0` — sufficient on its own |
| 2 | `EmitManagedLocalsZeroInit` -> `EmitZeroFrameSlot` (symtab.inc:11205) | 16-byte `rep stosb` |
| 3 | the NilPy watermarked pass, `ir_codegen.inc:11239`, seeded at `ScopeBase` | 16-byte `rep stosb` again |

plus a fourth on the result slot from `IR_ZERO_SYM`. Measured on a 1-arg,
3-local def: 8 `movq` + 9 `rep stosb` in one prologue, and the counts are
**identical at -O0, -O1, -O2 and -O3** — no pass removes any of them.

Pass 3 is redundant for every local that existed at prologue time, because
`ManagedLocalZeroBytes` — the table pass 2 uses — already covers `tyClass and
NilPyUserCode`, `tyAnsiString` and `tyVariant`. Its watermark starts at
`Procs[CurProc].ScopeBase` when it should start at the `SymCount` the prologue's
zero-init reached; the pass exists for locals minted *after* the prologue, and
that is the only set it should cover. Disabling it entirely (measurement only,
reverted) removes exactly one `rep stosb` per Variant local and nothing else.

**Priced, and small:** ~4% of the call, under the noise floor of a 3-run A/B at
box load 6.5. Recorded here rather than filed as its own ticket because the
single change that pays for all of it is this ticket's item 2 plus one watermark
seed, not a separate campaign. Whoever fixes item 2 should fix the seed in the
same pass; whoever does not, should not bother with the seed alone.


## Gate

`make compiler/pascal26` (the fixedpoint) plus `gate.sh quick`. This changes
prologue emission for every managed frame in every program, so it is a change
that wants Track T's full sweep against its sha before anyone leans on it, and
it should not be pinned the same day it lands.

## Not to be confused with

`0c3ad8a10` fixed the *instances* in `promocore.pas`. This ticket is the
*mechanism*, and closing it is what makes the next instance impossible rather
than merely absent.

## Raised p55 -> p65 (coordinator, 2026-08-30)

On frank-optimize's evidence, and on the count rather than the size of any one
win. **`promocore.pas:796` — "keep every hot routine free of the managed type" —
was violated three separate times in one day**, and frank-optimize fixed two of
them:

- the promotable-int hot paths carrying `TBig` (`e583ad825`);
- `PyVarSlotSet`'s unconditional `s := ''` on every variant slot copy including
  the integer path — a real 25-byte allocation under NilPy, because
  `PXX_NILPY_STR` deliberately makes a zero-length string real, so **the same line
  is free in Pascal and costs an allocation here**;
- and this ticket's own case, managed temps for a branch that is never taken.

frank-optimize's summary is the argument: *"that rule is enforced by nothing and
is forgotten silently at 20-40x."* An isolated repro on this one measured **44x**
— 20M calls, 0.294s against 13.060s, identical semantics, same never-taken
branch.

**Three independent violations in a day of a rule nothing enforces makes this a
root cause rather than a perf item.** It is the ticket that retires the rule by
making it unnecessary, which is worth more than any single site it fixes — the
tickets-closed-per-change measure `root-cause-over-microfix` asks for.

---

## RESOLVED — two causes, each about half the cost

Interleaved on one box (load 5.4-6.0), three rounds, `inline` arm, 20M calls,
every binary named because the tree moved between builds:

| binary | change | round 1 | 2 | 3 |
| --- | --- | ---: | ---: | ---: |
| `494fd9c21ad3` | HEAD, neither fix | 10.52 s | 9.77 | 9.93 |
| `bda1155557b2` | + epilogue all-zero guard | 5.10 s | 5.15 | 5.23 |
| `416c3640e2f0` | + per-arm flush | **0.43 s** | 0.45 | 0.44 |

`split` is 0.27 s on the same binary, so the 35-47x gap closes to ~1.6x. Both
arms still print `20000000`.

### Cause 1 — the finalize was emitted after the merge, not in the arm

`IRFlushPostCallIntf` finalizes by-value record argument temps, and `AN_SEQ`
called it **once per statement**. An `if` is one statement, so a temp created
inside a branch had its finalize emitted into the merge block and ran on **every**
call — including the calls that took the other arm. `PXXDBG=a.ir` shows it
plainly: three `default_mem` + `copy_rec_managed` pairs sitting in BB6, after
both arms have joined.

`AN_IF` now takes its own base after the condition is lowered and flushes at the
end of each arm. The condition's temps stay with the outer boundary, where they
belong — they are live across the branch. An `if` yields no value, so nothing
outside an arm can reference what the arm created.

**It cannot leak**, and this is the property that makes the change safe rather
than merely faster: a path that skips the sunk flush — `exit` from inside the
arm, a `goto` out — still meets `EmitManagedLocalCleanup` in the epilogue, which
visits every local unconditionally. The epilogue is the backstop.

### Cause 2 — an all-zero record still bought a heap lock

`EmitManagedLocalCleanup`'s record arm is an interface walk plus
`EmitAcquireHeapLock` / release / `EmitReleaseHeapLock`. Every managed field kind
releases to a no-op when its slot is zero, so **the lock round trip is the only
remaining effect** for an untouched temp. The repro has nine such temps and paid
**nine heap-lock round trips per call on a path that allocated nothing** — which
is the sentence that justifies the change, more than the multiplier does.

Guarded by a run-time all-zero test (`or` the record's qwords, `jz` past the
walk), bounded to <= 8 qwords so the test cannot exceed the block it guards.

**The two halves of item 2 are jointly effective, and a future reader must not
delete one.** The test is sound on its own — it reads the slot at run time, so a
record that owns something is never skipped — but what makes the fast path
actually *hit* is the zero-init contract, whose cheap word stores landed in
`991fa5c15`. Removing the prologue zeroing would silently disarm the epilogue
guard: still correct, no longer fast, and nothing would say so.

### Deliberately NOT done: the NilPy watermark seed

frank-optimize asked that whoever fixed item 2 also seed `PyZeroedUpTo`
(`ir_codegen.inc:11292`) at the prologue's `SymCount` rather than
`Procs[CurProc].ScopeBase`. **Not done, and not forgotten.** It needs a new
recorded high-water mark (nothing stores the prologue's `SymCount` today), it
lands in a pass whose own comments record three segfaults from getting zero-init
coverage wrong, and frank-optimize priced it at ~4% — under the noise floor of
its own measurement. Landing an unmeasurable risky change behind a 23x result is
how a later regression becomes unattributable. Filed as its own item rather than
folded in here.

### The rule this retires

`promocore.pas:796` — *"keep every hot routine free of TBig"* — was a correct
diagnosis and a workaround enforced by nothing, forgotten three times in one day.
The hand-splits in `promocore.pas` can now be measured against the unsplit form;
if they converge, the `*Slow` routines are unnecessary rather than mandatory.
That is a separate change and a separate measurement.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
