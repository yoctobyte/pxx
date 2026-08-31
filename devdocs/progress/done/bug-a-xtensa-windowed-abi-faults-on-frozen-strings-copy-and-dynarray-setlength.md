---
track: A+S
type: bug
prio: 50
status: done
found: 2026-08-30
found-by: frankS
owner: frankS
summary: "FIXED 2026-08-31 (5ac00ac71) after five rounds that killed every SHAPE hypothesis. It is a CONTENT property, exactly the class round 5 concluded was needed: the managed-string marshalling arms use a4-a7 because `a2-a7 survive call8` -- true of the Xtensa ABI, false of THIS COMPILER, which keeps the WINDOWED FRAME POINTER in a7 (EmitFrameAddrXtensa). Every concat and compare overwrote it; the next frame-relative local read faulted far from the cause. A07=00000001 in round 2's dump was literally the `movi a7, 1` the Char-operand arm emits, and it was set aside as `downstream, not load-bearing`. Call0 is byte-identical across the fix, proven. New sixth windowed canary, proven able to go red."
---

# The xtensa WINDOWED ABI bus-errors on frozen strings, Copy, and dynarray SetLength

Three constructs fault under `--xtensa-abi=windowed` and are correct under
Call0 (the default). All three predate the expression-stack fix in
[[bug-a-xtensa-has-no-ordered-string-compare-and-sorts-by-heap-handle]] —
**verified against the pre-change compiler**, which bus-errors identically, so
this is not fallout from that work.

## Repro

`--target=xtensa --platform=posix --xtensa-abi=windowed --xtensa-soft-mulhigh`,
under `qemu-xtensa` 10.2.1. Each is correct on Call0 and on x86-64.

```pascal
program t; var a: string[8]; begin a := 'zz'; WriteLn(Length(a)); end.
{ Call0: 2    windowed: SIGBUS  -- no comparison, no concat: a frozen string alone }

program t; var s: AnsiString; begin s := 'abcdef'; WriteLn(Copy(s, 2, 3)); end.
{ Call0: bcd  windowed: SIGBUS }

program t; var i: Integer; a: array of Integer;
begin SetLength(a, 50); for i := 0 to 49 do a[i] := i * 3; WriteLn(a[49]); end.
{ Call0: 147  windowed: SIGBUS }
```

The frozen-string case is the one to start from: it is the smallest, it
involves no helper call that the other two share, and it says the fault is in
how a *frozen buffer's address* is formed under windowed rather than in `Copy`
or `SetLength` themselves.

## Why this is only visible now

Windowed is the ESP-IDF ABI, and nothing could run a hosted xtensa binary until
`feature-a-hosted-xtensa-so-qemu-xtensa-can-be-an-oracle` landed the syscall,
exit and heap arms. On real IDF hardware these would have been three unexplained
crashes with no oracle to compare against.

**A caution for whoever takes it:** do not assume the windowed frame is the
suspect just because windowed is the failing arm. Call0 and windowed differ in
*two* independent ways — the register window, and the expression-stack direction
(`XtensaSlotOff`) — and the second was wrong on Call0 for months while windowed
was right. The arms are not "one correct, one broken"; they are two disciplines
that have each been wrong somewhere.

## Bound

Object-level plus observable output under qemu-xtensa 10.2.1, hosted profile,
both ABIs compared directly, at `e866cc16d4fe`. Not checked on real IDF
hardware.

## MEASURED 2026-08-30 (frankS) — TWO of the three were the data-section bug. `Copy` is NOT, and is still live.

All three repros run verbatim against the two builds that bracket
[[bug-a-a-perf-commit-silently-fixed-41-xtensa-windowed-divergences-and-nobody-knows-why]],
plus HEAD. Windowed, `--platform=posix --xtensa-soft-mulhigh`, qemu-xtensa:

| repro | `75d2ba662^` | `75d2ba662` | HEAD |
| --- | --- | --- | --- |
| `a: string[8]; a := 'zz'; WriteLn(Length(a))` | **SIGBUS** | `2` | `2` |
| `s := 'abcdef'; WriteLn(Copy(s, 2, 3))` | **SIGBUS** | **SIGBUS** | **SIGBUS** |
| `SetLength(a, 50); … WriteLn(a[49])` | **SIGBUS** | `147` | `147` |

`Copy` is deterministic (repeated), windowed-only — Call0 at HEAD prints `bcd`,
matching the x86-64 oracle.

### The frozen-string and SetLength arms are the DATA-SECTION alignment defect

They fault at the parent and pass at the child of a commit that touches
**`elfwriter.inc` only** — no backend, no IR — so nothing about how they are
CODED changed. They stopped faulting because the data section became 4-aligned.

**Not resolved, and this is deliberate.** They are green on a side effect of a
qemu performance fix, sized by `ELF_DATA_PAGE = 4096`; the alignment invariant
does not exist yet. Closing them would mark a live exposure resolved. They are
cross-referenced instead and go green for real when that ticket lands an explicit
invariant with a test.

### What this ticket is now ABOUT: `Copy` under windowed

One construct, still faulting at HEAD, which the alignment story does not
explain and never did.

**The ticket's own caution turns out to be the right one and is now evidence
rather than advice:**

> *do not assume the windowed frame is the suspect just because windowed is the
> failing arm … the arms are two disciplines that have each been wrong somewhere.*

Two of the three arms have now been explained by something that is not the
windowed frame at all — it is target-wide and hit Call0 programs too, just
fewer of them. Whatever is left in `Copy` is the residue after the loudest
shared cause was removed, which makes it a better-founded suspect than it was
when three constructs pointed three ways.

Starting point is no longer the frozen-string case (explained). It is `Copy`
itself: what address does the windowed arm form for the source or destination
buffer that the Call0 arm forms differently, given that a **frozen buffer alone**
(`string[8]`, no helper call) is now known to be fine at HEAD.

### Prio 40 → 50

Narrowed from three constructs to one, confirmed live at HEAD, and windowed is
the **ESP-IDF ABI** — the one real hardware uses — which has **no gated coverage
at all** ([[bug-a-the-xtensa-windowed-abi-is-compiled-twice-and-executed-never]]).
Not higher, because `Copy` under windowed is not on the path of a current
milestone and Call0 is the default everywhere hosted.

### Method note

All three repros were run as written rather than the two the alignment
hypothesis predicted. Had the hypothesis picked, `Copy` would have been swept
into the alignment ticket and closed with the other two — a live SIGBUS filed as
fixed by a commit that does not fix it.

## MEASURED 2026-08-30 (frankS), round 2 — it is a WINDOW UNDERFLOW, not an address `Copy` forms

Bound: HEAD `f17cd5607`, compiler binary sha256 **`cf30672a934e`** (self-host
fixedpoint verified, and confirmed unmoved only because no compiler source changed
since it was built), `qemu-xtensa`, `--platform=posix --xtensa-soft-mulhigh`.
Call0 and x86-64 both print `bcd`; windowed exits **135** (SIGBUS).

### 1. The alignment hypothesis is FALSIFIED

The obvious next suspect after the data-section story was misaligned word copying —
`PXXWordCopyOk` exists precisely to gate that, and SIGBUS is what a misaligned
32-bit access raises. It is wrong. Every `(index, count)` pair in a 5x5 sweep
faults, **including `Copy(s,1,4)`** — word-aligned start, whole number of words,
the case a misaligned word loop cannot reach:

| | n=1 | n=2 | n=3 | n=4 | n=8 |
| --- | --- | --- | --- | --- | --- |
| i=1..5 | SIGBUS | SIGBUS | SIGBUS | SIGBUS | SIGBUS |

The fault is **unconditional in `Copy`** and does not depend on the data at all.
`PXXWordCopyOk` reads correctly for non-x86 (`(n >= SizeOf(NativeInt)) and
(((d or s) and (SizeOf(NativeInt)-1)) = 0)`) and is not implicated.

### 2. It is not "any string helper", and the result is never consumed

| program | windowed |
| --- | --- |
| `r := Copy(s,2,3);` — **result never used** | **SIGBUS** |
| `WriteLn(Copy(s,2,3))` | SIGBUS |
| `r := Copy(s,n,3)` (variable index) | SIGBUS |
| `i := Pos('cd', s)` | ok, `3` |
| `r := s + 'x'` | ok, `abcdefx` |
| `WriteLn(s)` | ok, `abcdef` |

The result-unused row is the one that matters: it removes `WriteLn`, `Length` and
every consumer from the picture. Concat and `Pos` both marshal string arguments
through the same expression stack and both survive, so the defect is not the
string-helper calling convention in general.

### 3. What actually faults, measured rather than inferred

`qemu-xtensa -d in_asm,cpu`, final CPU state:

```
EPC1=08057bdc   EXCCAUSE=00000001
WINDOWBASE=00000002   WINDOWSTART=00000004
```

`0x08057bdc` is a **`retw.n`**. `WINDOWSTART=4` (binary `100`) says exactly one
frame is live, so the `retw` needs the caller's registers reloaded from the stack —
a **window underflow** — and the reload is what dies.

**So the fault is in the register-window machinery, not in a pointer `Copy`
computes.** That redirects this ticket's own starting question:

> *what address does the windowed arm form for the source or destination buffer
> that the Call0 arm forms differently*

It forms none. There is no bad data address; there is a `retw` whose underflow
handler cannot reload through the frame it was given.

*(The post-fault A-register view shows `A07=00000001` where a7 is the windowed
frame pointer, and a following block would compute `addi a2, a7, -32`. That is
downstream of a failed window restore and is NOT load-bearing evidence — recorded
so the next reader does not chase it as the cause.)*

### 4. The invariant at stake, and where the audit should start

The windowed contract is documented three times in `ir_codegen_xtensa.inc`, in the
headers of `XtensaPushA2`, `XtensaSlotOff` and `XtensaDropSlots`:

> *Windowed keeps sp fixed — moving it desyncs the window spill area at `[sp-16]`.*

That is exactly the area a window underflow reloads from. **A stray sp move under
windowed produces precisely this failure**, and it produces it at a `retw` that can
be an arbitrary distance from the offending code — the classic "plausible wrong
state far from the cause" shape.

The three expression-stack helpers honour the invariant correctly. So the suspect
is an **unguarded `sp` adjustment on `Copy`'s path**. There are ~20
`xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, …)` sites in the file; the two sampled
(`:1155`, `:3011`) sit correctly inside Call0-only branches, and **the rest are not
yet audited**. That audit is the next step, and the ticket's own caution still
applies to it — the arms are two disciplines, and the windowed one being the
failing arm does not make every difference between them the cause.

Not yet established: which site, and why `Copy` reaches it while `Pos` and concat
do not.

## Round 3 (frankS) — the differential names a real ABI violation, and a prediction test then FALSIFIED the easy mechanism

Coordinator's steer, and it was the right one: `Pos`/concat pass while `Copy`
faults, so the discriminator is computable and beats reading ~20 `sp` sites.

### The `sp`-movement survey did NOT discriminate

`qemu-xtensa -d in_asm` on both paths, counting executed `addi a1, a1, …`:

| program | executed sp-adjusts |
| --- | --- |
| `Copy` (**faults**) | 5 |
| `Pos` (passes) | 8 |

**The passing path moves `sp` more often than the failing one.** Raw sp movement
is not the discriminator, which is evidence against the easy reading of the
"stray sp move" hypothesis rather than for it.

### What the trace DID find: every windowed frame violates the ABI the same way

Every executed prologue, without exception:

```
0x080576d8:  entry  a1, 32          <- allocates 32 bytes, establishes the window frame
0x080560e6:  addi   a1, a1, -112    <- then moves sp another 112 bytes with plain arithmetic
```

Ten `entry` sites executed, **all with immediate 32**, each followed by an
`addi`/`addmi` of -96 or -112. Confirmed in source: `symtab.inc:10779/10784`, the
**windowed** arm, patches `EncodeXtensaAddi`/`EncodeXtensaAddmi` on
`reg_xtensa_sp` for `size + XtSpillMax`.

**Under the windowed ABI `a1` may only be moved by `MOVSP` (or by `entry`'s own
immediate).** The caller's 16-byte register save area sits at `[a1-16]`, and
`MOVSP` exists precisely because a plain add relocates the stack pointer while
leaving that area behind. This is the same invariant the file documents three
times — *"windowed keeps sp fixed, moving it desyncs the window spill area at
[sp-16]"* — except the violation is in the **prologue**, not in the
expression-stack helpers, which honour it correctly.

### The fault, restated from round 2

`EPC1=08057bdc` is a `retw.n`; `EXCCAUSE=1`; `WINDOWSTART=4`. A window underflow
whose reload dies. That is exactly the failure a desynced save area produces.

### PREDICTION TEST — and it FAILED, which is why this is not yet the root cause

If the mechanism were "the plain `sp` move desyncs the save area, and a deep
enough chain wraps the register file and reads it", then **any** sufficiently deep
call chain must fault, with `Copy` incidental. Tested with no strings, no helpers,
no `Copy` — plain recursion 24 deep, which comfortably wraps an 8-window file:

```
depth-24  call0     rc=0  24
depth-24  windowed  rc=0  24
```

**Both pass.** So the plain-`addi` violation is real and is present in every
frame, but it is **not sufficient on its own** to produce the fault. Something
about `Copy`'s path supplies the missing ingredient.

The most likely remaining shape, stated as the next hypothesis and **not** as a
finding: the desync only bites when `a1` changes *between* an overflow spill and
its matching underflow reload, which depends on where the `addi` sits relative to
the calls — an ordering property, not a depth property. That is testable and has
not been tested.

### Status

- **Measured:** the fault is an underflow at `retw`; every windowed prologue moves
  `sp` with a plain `addi` after `entry`, which violates the windowed ABI; the
  source site is `symtab.inc:10779/10784`.
- **Falsified:** misaligned word copy (round 2); "sp moves more on the failing
  path" (this round); "plain sp move + call depth is sufficient" (this round).
- **Not established:** what `Copy` supplies that `Pos`, concat and deep recursion
  do not. That remains the discriminator and it is still the cheaper question.

Nothing has been changed in the compiler. The `symtab.inc` finding is a Track A
shared-file matter and this lane holds `ir_codegen_xtensa.inc` only.

## Round 4 (frankS) — a fourth hypothesis dead, and the window-state differential separates the two paths cleanly

### The ordering hypothesis is dead, from data already collected

Round 3's next candidate was that the desync bites only when `a1` changes
*between* an overflow spill and its matching underflow reload — an ordering
property. That requires a **mid-body** `sp` move. There is none. Every executed
`addi a1, a1, …` in the faulting path sits exactly **6 bytes after its `entry`**:

| addi | entry | delta |
| --- | --- | --- |
| `0x08053c52` | `0x08053c4c` | 6 |
| `0x08054652` | `0x0805464c` | 6 |
| `0x080560e6` | `0x080560e0` | 6 |
| `0x0805deca` | `0x0805dec4` | 6 |
| `0x080898aa` | `0x080898a4` | 6 |

All five are prologue-local. `a1` changes **once**, before the function makes any
call, so it cannot differ between a spill and its reload. Killed without writing a
program, by checking arithmetic on the trace already in hand.

### The window-state differential — the right quantity, and it separates them

`qemu-xtensa -d cpu`, `WINDOWBASE`/`WINDOWSTART` over the run (hex):

| | `Copy` (**faults**) | `Pos` (passes) |
| --- | --- | --- |
| WINDOWSTART values seen | `55`, `51`, `50`, `14`, `10`, `04` | `01`, `05`, `0f` |
| WINDOWBASE reached | **6** | 4 |

`Pos` never sets a bit above 3 and stays inside the physical register file.
`Copy` sets bits up to **6** and wraps it, so its returns must reload spilled
frames **from memory**, which `Pos` largely never has to do.

The last three states before the fault:

```
wb=4 ws=10      (only the current frame live)
wb=4 ws=14      (frames 2 and 4)
wb=2 ws=04      <- retw here: only the CURRENT frame is live, so the caller
                   must be reloaded from the stack. That reload faults.
```

**So the discriminator is real register-file wrap plus an underflow reload from
memory** — a state property, exactly as suspected, and not any difference in
which code the two paths execute.

### But this does NOT yet finish it, and the depth test is why

Plain recursion 24 deep also wraps the file and also reloads from memory, and it
**passes**. So "wraps and reloads" is necessary but not sufficient, the same way
the `sp` violation was. The remaining difference between the recursion case and
the `Copy` case is the **frame size**: the recursion frame is `entry a1, 32` plus
a small `addi`, while every frame on `Copy`'s path is `entry a1, 32` plus **-96 or
-112**.

That is the next hypothesis and it is **not a finding**: the reload may be correct
for small frames and wrong once the `addi` extension is large, which would tie
this ticket back to
[[bug-a-xtensa-windowed-prologue-moves-sp-with-a-plain-addi-instead-of-movsp]]
after all — a connection round 3 explicitly could not support.

**The consequence to derive and test first:** a program with no strings and no
`Copy`, whose recursion is deep enough to wrap the file *and* whose frames are
large enough to force a big prologue `addi` (a sizeable local array in the
recursive function). If that faults, the mechanism is frame-size-dependent
underflow and `Copy` is incidental. If it passes, frame size is not it either and
a fifth hypothesis is needed.

**Not yet run.** Recorded so the next session tests the prediction rather than
adopting the story.

### Falsified so far

1. Misaligned word copy (round 2) — 5x5 sweep, every cell faults incl. aligned.
2. "The failing path moves `sp` more" (round 3) — it moves it *less*: 5 vs 8.
3. "Plain `sp` move + call depth is sufficient" (round 3) — depth-24 passes.
4. "The desync needs `a1` to change between spill and reload" (round 4) — no
   mid-body `sp` move exists; all five are prologue-local.

## Round 5 (frankS) — the prediction was RUN, it failed, and it EXONERATES the prologue ticket

Round 4 derived a consequence and left it untested. Tested now.

`deepbig.pas`: no strings, no `Copy`, recursion 24 deep, each frame carrying a
112-byte local array so the prologue is a big `addi` like every frame on `Copy`'s
path.

```
deep24+112B  call0     rc=0  24
deep24+112B  windowed  rc=0  24
```

**Passes.** And — the part that makes this a real test rather than a null result —
**it reproduced the conditions exactly.** Verified rather than assumed:

| condition | `Copy` (faults) | `deepbig` (passes) |
| --- | --- | --- |
| prologue shape | `entry a1, 32` + `addi a1, a1, -112` | **identical**, `-112` and `-96` |
| WINDOWBASE reached | 6 | **6** |
| WINDOWSTART range | `55 51 50 14 10 04` | **`55 54 50 45 15 14 10 05 04`** |
| reaches the fault state `wb=2 ws=04` | yes — and dies | **yes — and returns fine** |

A program that reaches the **identical window state**, with **identical frame
shapes**, wrapping the register file to the same depth, does not fault.

### What this rules out, and it is the useful half

- Frame size is not the missing ingredient.
- The prologue `addi` is not sufficient **even at the same sizes**.
- Register-file wrap is not sufficient **at the same depth**.
- Reaching `wb=2 ws=04` and reloading a caller from memory is not sufficient
  **in the same state**.

**This is measured evidence that
[[bug-a-xtensa-windowed-prologue-moves-sp-with-a-plain-addi-instead-of-movsp]]
does not cause this fault.** That ticket was filed separately on the epistemic
grounds that *"violates the ABI" and "causes this fault" are different claims*;
round 5 turns that caution into a result. The prologue divergence is real,
confirmed against gcc, and **exonerated as the cause of the `Copy` SIGBUS**. The
two tickets should not be merged, and the prologue one should not be raised on
this ticket's evidence.

### Where that leaves the discriminator

Every *structural* explanation is now dead: the code path, the `sp` movement, the
frame size, the wrap depth, and the window state at the fault are all matched by a
program that works. What remains must be something about **what `Copy` puts in
those frames or reloads out of them** — a content or address property rather than
a shape property. That is a different class of hypothesis than rounds 1-5 and the
instruments so far have all been shape instruments.

Still unestablished, and no narrower than it was: **what `Copy` supplies that
`Pos`, concat, deep recursion and deep-recursion-with-large-frames do not.**

### Falsified, complete list

1. Misaligned word copy — 5x5 sweep, every cell faults including aligned.
2. "The failing path moves `sp` more" — it moves it less: 5 vs 8.
3. "Plain `sp` move + call depth is sufficient" — depth-24 passes.
4. "The desync needs `a1` to change between spill and reload" — no mid-body `sp`
   move exists; all five are prologue-local, 6 bytes after `entry`.
5. "Wrap + reload + large frames is sufficient" — a program matching all of it,
   including the exact fault state, passes.

---

## PARKED 2026-08-30 (frankS) — released from `working/`, no code touched

Moved to `unfinished/` because the session is ending, not because the work is
blocked. **The live lock in `working/` was the only thing here that needed
releasing**: this ticket produced five falsifications and zero edits, so there is
no half-applied compiler change to revert and no stable-binary risk — the tree is
clean and `compiler/**` is untouched by this ticket.

**Resume state — everything needed is above, nothing is in a session's head.**

- **Do not re-run rounds 1-5.** The falsified list is complete and each entry
  names the measurement that killed it. Round 5 in particular cost a program that
  reproduces the exact fault state (`wb=2 ws=04`) and *passes*; re-deriving it is
  the expensive mistake available here.
- **The next instrument must be a different class.** Rounds 1-5 were all *shape*
  instruments (path, `sp` delta, depth, frame size, window state). Every shape
  explanation is now matched by a working program, so the remaining hypothesis is
  a **content or address** property of what `Copy` puts into or reloads out of
  those frames. No such instrument has been built yet — that is the open work.
- **Do not raise
  [[bug-a-xtensa-windowed-prologue-moves-sp-with-a-plain-addi-instead-of-movsp]]
  on this ticket's evidence.** Round 5 exonerated it as the cause here. It is a
  real ABI divergence, confirmed against the gcc oracle, and it stands on its own
  separate grounds.

`owner:` stays `frankS` as attribution for the five rounds, **not as a claim** —
it is unheld and free to take. A fresh session with context to spend is arguably
the better holder now, since what it needs next is a new instrument rather than
more analysis of the existing measurements.


## Round 6 (frankS, 2026-08-31) — FIXED. It was a CONTENT property, and round 2 had it in its hands

`5ac00ac71`. Round 5 ended: *"what remains must be something about what `Copy`
puts in those frames — a content or address property rather than a shape
property."* That was right, and the content in question is **which register
holds what**.

### The defect, in one sentence

`ir_codegen_xtensa.inc`'s managed-string concat and compare arms marshal their
operands into **a4-a7**, and the comment says why — *"a2-a7 survive call8"* —
which is **true of the Xtensa windowed ABI and false of this compiler**, because
`EmitFrameAddrXtensa` puts the **windowed frame pointer in a7**:

```pascal
if XtensaABI = XTENSA_ABI_WINDOWED then fp := reg_xtensa_a7 else fp := reg_xtensa_a15;
```

So every concat and every compare overwrote the frame pointer, and the next
frame-relative local access read from garbage.

### Measured

`qemu-xtensa -d in_asm,cpu` on `r := Copy(s, 2, 3)`, the last block executed:

```
0x080876fe:  addi a2, a7, -32     <- a frame-relative local
0x08087701:  l32i a2, a2, 0       <- loads from 0xFFFFFFE1.  SIGBUS.

A07=00000001
```

**`A07=00000001` is literally the `movi a7, 1` that the Char-operand arm emits
for `lenB`** (`EmitLoadConstXtensa(reg_xtensa_a7, 1)`, the "neither ansistring
nor frozen" branch). Not a corrupted value — the value the compiler asked for,
in the register the compiler had reserved for something else.

### The part worth carrying: round 2 saw this and set it aside

Round 2's own words:

> *(The post-fault A-register view shows `A07=00000001` where a7 is the windowed
> frame pointer, and a following block would compute `addi a2, a7, -32`. That is
> downstream of a failed window restore and is NOT load-bearing evidence —
> recorded so the next reader does not chase it as the cause.)*

Every clause of that is accurate except the verdict. a7 *is* the windowed frame
pointer — round 2 says so — and the `addi a2, a7, -32` *is* the faulting
instruction. It was classified as downstream because a **more interesting
story** was already in hand (`retw`, `WINDOWSTART`, a window underflow), and the
register reading as a plausible consequence of that story fitted it.

The guard that would have caught it is the one this repo keeps arriving at from
other directions: **ask what this would be if it were false.** If `A07=1` were
NOT downstream, it would be a value someone deliberately put there — and one
`grep reg_xtensa_a7` on the file answers that in seconds. Rounds 3, 4 and 5 cost
three programs and five falsifications between that note and this grep.

The four earlier rounds are **not wasted** and should not be re-run: they are
what proved the shape explanations dead, and it was round 5's *"every shape
explanation is now matched by a working program"* that made a content instrument
the only remaining move.

### The fix

`XtensaMarshalReg4` returns **a3 under windowed, a7 on Call0**, and both
marshalling arms ask it instead of naming a7. a3 is free at that point on both
ABIs: the operands are already pushed to expression slots, `IREmitNodeXtensa`
leaves its value in a2, and the quad is consumed into a10-a13 (windowed) or
a2-a5 (Call0) before anything else runs.

### Controls, both directions

| | result |
| --- | --- |
| **Call0 codegen unchanged** | the same source through the pre-fix and post-fix compilers produces a **byte-identical ELF** (`ea0dbee7cd3c`) |
| **windowed, pre-fix** (`1860af97a4aa`) | **signal 7, rc 135**, output truncated mid-`Copy` — both gate slots fire |
| **windowed, post-fix** | matches the x86-64 oracle byte for byte |

And the ticket's three original repros, all green under windowed:
`string[8]` + `Length`, `Copy(s,2,3)`, `SetLength(a,50)` + `a[49]`. Plus a 5x4
`Copy(i,n)` sweep, concat and compare over every operand shape, and `Pos`.

### Test

**`test/test_cross_managed_strings.pas`**, new: concat, compare and `Copy` over
every operand shape the marshalling arms distinguish (ansistring, frozen string,
Char), **with a local read after every helper call**. That last part is the
actual assertion and it is why an obvious test would not have worked: **the
helper's own result was never wrong.** A row checking only the returned string
passes on the broken compiler. What broke was everything the function did
afterwards through its frame pointer.

Wired as the **sixth windowed canary** in `test-xtensa`, alongside a **Call0 row
that exists as the control** for the ABI split rather than as extra coverage —
so a later edit that "simplifies" `XtensaMarshalReg4` away has to break
something visible.

The `test-xtensa` header comment is corrected in the same commit: it still said
windowed faults on frozen strings, `Copy` and `SetLength`. All three pass.

### What this does NOT resolve

- **`bug-a-xtensa-windowed-prologue-moves-sp-with-a-plain-addi-instead-of-movsp`
  stays open and stays exonerated.** Round 5 measured that it does not cause this
  fault; round 6 names a cause that is not it. The ABI violation is still real
  and still unfixed — it just was not this.
- The frozen-string and `SetLength` arms remain green on the **data-section
  alignment side effect** described above, not on an asserted invariant. That is
  the other ticket's job and is unchanged by this.

## Log
- 2026-08-31 — resolved, commit PENDING-COMMIT.
