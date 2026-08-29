---
track: A
prio: 70
type: bug
blocked-by: []
summary: "HeapMmap in compiler/builtin/builtinheap.pas is a chain of per-target {$ifdef}s with no wasm32 arm, so on wasm32 it assigns Result nothing and returns 0. PXXAlloc does not check the result (on Linux a failed mmap returns a negative errno that faults on access), so the heap bump pointer starts at 0 and hands out addresses 8, 32, 56... Measured: two objects at 8 and 32, both readable and correct. It works until roughly 1 KB has been allocated and then silently overwrites BSS, because address 0 is a legal wasm address with no page protection. Fix is one additive arm, exactly the shape the PXX_ESP static arena already has."
status: done
owner: frankA
---

# `HeapMmap` has no wasm32 arm, so the heap starts at address zero

- **Type:** bug (RTL / builtin heap) — **Track A** (`compiler/builtin/**`).
- **Filed:** 2026-08-28 by the wasm32 lane (branch `wasm`), which cannot fix it
  under its own standing rule: a phase needing a shared-file edit files a
  Track A ticket rather than making the edit.
- **Blocks:** the wasm32 target having a usable heap at all. Everything
  downstream of allocation — classes, managed strings, dynamic arrays,
  variants — currently runs on a heap that overlaps low memory.

## The bug

`HeapMmap(len)` (`compiler/builtin/builtinheap.pas:672`) is a chain of
per-target `{$ifdef}`s:

```pascal
{$ifdef CPUX86_64}  Result := __pxxrawsyscall(9,   0, len, 3, 34, -1, 0); {$endif}
{$ifdef CPUAARCH64} Result := __pxxrawsyscall(222, 0, len, 3, 34, -1, 0); {$endif}
{$ifdef CPU_ARM32}  Result := __pxxrawsyscall(192, 0, len, 3, 34, -1, 0); {$endif}
{$ifdef CPU_I386}   Result := __pxxrawsyscall(192, 0, len, 3, 34, -1, 0); {$endif}
{$ifdef CPU_RISCV32}{$ifndef PXX_ESP}
                    Result := __pxxrawsyscall(222, 0, len, 3, 34, -1, 0); {$endif}{$endif}
{$ifdef PXX_ESP}    { static arena, handed out once } {$endif}
```

`CPU_WASM32` matches none of them (the define exists — `lexer.inc:987`), so
**`Result` is never assigned and the function returns 0.**

`PXXAlloc` does not check it (`builtinheap.pas:911`):

```pascal
HeapPtr := HeapMmap(arena);
HeapEnd := HeapPtr + arena;
```

That is deliberate on a hosted target: a failed `mmap` returns a **negative**
errno and the next access faults. **On wasm32 there is nothing to fault on.**
Address 0 is a legal linear-memory address, a load from it returns zero, and
linear memory has no page protection — so the allocator bumps happily from 0.

## Measurement

A two-object program compiled `--target=wasm32` and run under node:

```
addr1 = 8    addr2 = 32    delta = 24
code1 = 11   code2 = 22          <- both objects read back correctly
memory bytes = 131072   sp = 110544
```

The objects work. That is the problem: the wasm32 lane's virtual-dispatch
differential passes 7 of 7 against the native build on this heap. **It stays
correct until about 1 KB has been allocated, and then writes into BSS** — the
module's globals start at 1024.

## The fix, and why it is small

**One additive arm, the shape `PXX_ESP` already has.** A static arena in BSS,
handed out once, with `Result := 0` on a second request (which is what every
other target's failure looks like):

```pascal
{$ifdef CPU_WASM32}
  { Linear memory has no page protection and address 0 is legal, so there is
    nothing for a failed allocation to fault on -- the arena must be real
    storage, not a syscall result. Same shape as PXX_ESP: BSS, 8-aligned,
    handed out once. The module's declared page count follows BSSSize, so
    reserving it here is what makes the memory exist. }
  if WasmArenaUsed <> 0 then Result := 0
  else begin WasmArenaUsed := 1; Result := Int64(@WasmArena[0]); end;
{$endif}
```

BSS is zero at instantiation in wasm (linear memory starts zeroed), so unlike
the ESP arm this one does **not** need to zero the arena on hand-out — the
zero-init contract `PXXAlloc` documents is satisfied for free. Say so in the
comment; it is the one line of that block that differs from ESP's and it would
otherwise read as an omission.

Arena size: `HEAP_ARENA` is already 65536 under `PXX_ESP` and 256 MiB
otherwise. wasm32 wants its own — large enough to be useful, small enough that
every module does not declare a huge minimum memory. A few MiB is a reasonable
first number; it is a `{$ifdef}` on the constant at `builtinheap.pas:581`.

**`memory.grow` is the eventual answer and is NOT this ticket.** It needs a new
intrinsic (`__pxxmemorygrow`) and therefore a new token in `defs.inc`, a parser
arm, an AST/IR node and a backend arm — the hottest shared files in the tree,
for a target that does not yet need to grow. A fixed arena is what ESP shipped
and it is enough until the compiler itself runs under wasm.

## Why the wasm lane cannot do this itself

Standing rule for the `wasm` branch (`devdocs/dev/wasm/PLAN.md`): *if a phase
needs a shared-file edit, that is a signal to file a Track A ticket and wait —
never to make the edit here.* `compiler/builtin/builtinheap.pas` is compiled
into every program on every target. The change is additive and target-guarded
and cannot alter another target's output, but that judgement is the ticket's to
record, not the branch's to act on.

## What the wasm lane has done in the meantime

The backend's `GetMem` lowering is correct and is staying: it calls `PXXAlloc`
like every other backend, stores the VMT pointer, runs the constructor and
returns the instance. The defect is one function below it. Virtual dispatch,
interfaces and construction all work today — **on a heap that starts at zero**,
which is recorded as a known limitation in `PLAN.md` and in
`test/wasm/check_calls.sh` rather than being allowed to read as a passing
milestone.

## Gate

Per `CLAUDE.md`: `make compiler/pascal26` (the byte-identical self-host
fixedpoint) plus the repro. The repro is the two-object program above; assert
the returned addresses are above the module's BSS top, not merely non-zero.
Other targets are untouched by construction, but `gate.sh quick` is cheap and
this file is compiled by all of them.

## 2026-08-28 — re-measured, and one fact the original report did not have

The managed-string phase is the first thing on this target that allocates in
anger, so the arena was measured again rather than inferred:

```
$ cat probe.pas
program AllocProbe;
var i: Integer; p: Pointer;
begin
  for i := 1 to 12 do begin p := PXXAlloc(1000, 8); writeln(i, ' ', NativeInt(p)); end;
end.

$ pascal26 --target=wasm32 probe.pas probe.wasm && node run.js probe.wasm
1 8
2 1016
3 2024
...
12 11096
```

Address 8, then a straight bump. BSS starts at `WASM_BSS_BASE = 1024`, so the
third allocation is already inside it.

**The new fact: it does not merely corrupt, it eventually traps.** The module
declares `(memory 2)` — 128 KB — and never calls `memory.grow`, so a program
whose live heap passes about 128 KB dies with `RuntimeError: memory access out
of bounds`. Demonstrated by filling each block:

```
addr sentinel 43300
alloc 8
alloc 1016
alloc 2024
TRAP: memory access out of bounds
```

So the wasm32 failure ladder is: silent corruption of the null guard, then of
BSS, then of the data blob and the shadow stack, and finally a trap — the
*correct* diagnosis arriving only after everything it could have reported is
already gone.

**Any fix therefore has two halves, not one.** The `PXX_ESP` static-arena shape
named in the original report gives a correct BASE but a fixed CEILING, which on
this target means a program that dies at a size the host could trivially have
granted. wasm's native `sbrk` is `memory.grow`, which returns the previous size
in pages — but there is no way to reach it from Pascal today: the wasm32
backend has no lowering for it and no intrinsic is declared. So the arm needs
an RTL change (Track A, this ticket) **and** a backend intrinsic (the wasm32
lane), and the two should be designed together.

**What now depends on it:** managed strings publish correctly as of the phase
landed today, and `test/wasm/check_managed.sh` passes — but only because its
live set is a handful of short strings the free list recycles inside the first
kilobyte. That script asserts `PXXAlloc` still returns an address below 1024,
so **it will FAIL by design the day this ticket lands**, which is the signal to
rewrite its scope note and re-measure the slice at a realistic size.

---

## GRANT, 2026-08-29 — the arena arm is RELEASED to Track A. Written fresh, not merged.

Filed here rather than left in message traffic, because an authorisation is a
finding about what is permitted and an unfiled grant does not read as missing —
it reads as covered.

**What is released:** writing the wasm32 static-arena arm **fresh on master**,
under Track A, in the shape this ticket already specifies and the shape
`PXX_ESP` already ships. Whoever holds Track A may take this at p70 without a
wasm grant of any kind.

**What stays ungranted, unchanged:** merging frankwasm's branch work. `75c0b7488`
is on `origin/wasm` and is not an ancestor of master; nothing on that branch is
pre-approved, and the wasm-arms ledger
(`feature-a-merge-the-wasm-branch-the-shared-file-arms` [A p40]) still governs
five arms across two lanes. **Branch permission is not merge permission.**

### Correcting my own gate — "never the RTL arm alone" does not apply here

I had been holding this ticket on a two-halves rule: the RTL arena arm and the
`memory.grow` intrinsic land together or neither lands. frankA asked me to say
whether that still binds. Re-derived against the ticket instead of repeating it,
**it does not, and the ticket says so in its own body**:

> `memory.grow` is the eventual answer and is **NOT this ticket**. It needs a new
> intrinsic (`__pxxmemorygrow`), a new token in `defs.inc`, and a parser change —
> for a target that does not yet need to grow.

The two-halves rule came from the **merge ledger**, where the hazard is taking
half of a branch's coupled work. It was carried across to this ticket by slug
association and it does not transfer: **the arena is not half of anything.** It
is the complete fix for a target that never grows its heap, which is precisely
what ESP shipped and has run on since.

**And the arithmetic runs the other way from the gate.** Today the heap bump
pointer starts at **0**, hands out 8/32/56, reads back correctly, and begins
overwriting BSS at roughly 1 KB — silent memory corruption with no fault,
because address 0 is a legal wasm address with no page protection. A fixed arena
that eventually exhausts gives a **clean, checkable failure**. Holding the arena
back until `memory.grow` exists keeps silent corruption in place in order to
avoid shipping a heap that cannot grow. That is the wrong direction on every
axis: the gate was protecting the more dangerous state.

**The general shape, since this is the third time this week:** a constraint
earned in one context, carried to a neighbouring ticket by name rather than by
its reason, and then re-justified every time it was restated because restating
is cheaper than re-deriving. It survived three restatements in the coordinator's
own prompt. **A gate whose original reason is not re-checked is indistinguishable
from a gate that is still correct** — and the ticket it was blocking contained
the refutation in plain prose the whole time.

**Do not** add `{$error}` to the missing arm. `builtinheap.pas` compiles into
every program on every target; a terminal directive there refuses every unported
build, including programs that never allocate. See the correction appended to
`bug-a-per-cpu-ifdef-chains-in-builtinheap-fail-open`.

---

## LANDED 2026-08-29 (frankA, Track A) — arena arm + exhaustive chain

Written fresh on `master` under the grant above. No wasm-branch code merged.

### What landed

1. **`HeapMmap` is now one exhaustive `{$if}/{$elseif}/{$else}` chain** instead of
   a run of independent `{$ifdef}` blocks — the same restructure `1ea3bdb85`
   applied to the five `PXXSys*` chains, applied to the instance with the largest
   blast radius. `PXX_ESP` is tested **first** because bare riscv32 defines both
   `PXX_ESP` and `CPU_RISCV32` and wants the arena arm.
2. **A `CPU_WASM32` arm**: a 1 MiB BSS arena (`WasmArena`, `Int64` cells so the
   base is 8-aligned), handed out once.
3. **`HEAP_ARENA` gets a wasm32 arm of exactly 1 MiB.** *This is load-bearing and
   was nearly missed:* `PXXAlloc` rounds every request up to `HEAP_ARENA` and then
   sets `HeapEnd := HeapPtr + arena`. Left at the 256 MiB default, `HeapEnd` would
   have pointed 255 MiB past a 1 MiB buffer and the bump pointer would have walked
   straight out of it — reintroducing the corruption this arm removes, from a
   constant three hundred lines away from the arm.
4. **A terminal `{$else} Result := -1`.**

### Two deliberate differences from the `PXX_ESP` shape

Both are the reason the arm exists, so both are commented in place:

- **No zeroing on hand-out.** wasm linear memory is zero at instantiation, so
  `PXXAlloc`'s zero-init contract is free. ESP cannot assume that; we can.
- **Exhaustion returns `-1`, not `0`.** ESP returns 0 because 0 faults there and
  reports OOM for free. On wasm that idiom *is the bug*: 0 is legal, reads as
  zero, has no page protection. `-1` is out of bounds on first touch.

### Terminal arm: NOT `{$error}` — measured, not preferred

pxx-a5 and the coordinator both raised `{$error}` as arguable here, on the
reasonable ground that a program allocating nothing is close to hypothetical.
It is still wrong, for a reason that is a property of the file rather than a
judgement call:

**`HeapMmap` is compiled unconditionally — it is not inside `{$ifndef
PXX_ESP_IDF}` — while the ESP-IDF profile redefines `PXXAlloc` to use
`calloc`/`free` and never calls it** (`builtinheap.pas`, the `PXX_ESP_IDF`
block). A compile-time refusal would therefore break every xtensa and riscv32
IDF build over a function those builds do not use, and Track S is live.

The general rule, same as the syscall chains: **terminal arms are chosen by
reachability.** `{$error}` where a missing arm cannot be reached at run time; a
defined failure value where the routine is compiled into everything and called
by almost nothing.

### Non-regression — this file compiles into every program on every target

An A/B of the same source through a compiler built with and without the change:

| target | OLD vs NEW output |
| --- | --- |
| x86-64 / aarch64 / arm32 / i386 / riscv32 | **byte-identical** |
| xtensa `--esp-profile=bare`, riscv32 `--esp-profile=bare` | **byte-identical** |
| the compiler binary itself (9.3 MB) | **byte-identical**, `b2dff2c3cbf9` |

**With a positive control, because seven identical results prove nothing if the
code is unreachable.** Perturbing the x86-64 arm (mmap `9` -> `900`) and
rebuilding **segfaults during the self-host** — `HeapMmap` is reached, is
load-bearing, and a real change to it does move the artifact. Reverted; the
restored binary is byte-identical to NEW again.

### NOT VERIFIED, and it is the arm itself

**Master's wasm32 backend is a stub** — `--target=wasm32` on any allocating
program dies at `builtinheap.pas:467: wasm32: code generation not implemented`,
well before `HeapMmap`. The working backend is on the unmerged `wasm` branch, and
merging it is explicitly ungranted. So on master this change is proven to be
*correct Pascal that changes no other target*, and **the wasm behaviour is
unproven here**. What is verified: the file parses with `CPU_WASM32` defined, so
the chain is well-formed and the arm is selectable.

`WasmArena : array[0..131071] of Int64` = 131072 x 8 = 1048576 = `HEAP_ARENA`.
That equality is the one silent failure mode left; it is asserted only by
inspection.

**Handing the verification to the wasm32 lane** (frankwasm), which asked to be
pinged at the commit.

> **CORRECTION 2026-08-29, and the wrong version is kept because this ticket
> published it.** This section first said the assertion to use is *"`PXXAlloc`
> must return an address **above** the BSS top (`WASM_BSS_BASE + BSSSize`)"*.
> **That is wrong, and it would have failed on the very fix it was written to
> validate:** the arena IS in BSS, so a correct allocation lands *inside*
> `[WASM_BSS_BASE, WASM_BSS_BASE + BSSSize)`, not above it. Measured by the wasm
> lane: first allocation at 39152, BSS running from 1024 for ~1 MiB. It came from
> that lane and I relayed it into this ticket without re-deriving it against the
> arm actually being built — the assertion was shaped for the mmap-style fix
> originally imagined. Same page, same message, both facts present: BSS feeds the
> declared page count *and* the arena lives in BSS. Neither of us put them
> together.

**The assertions that actually hold** (`test/wasm/check_managed.sh`, each arm
falsified individually before being trusted):

- `base >= 1024` — clears the null guard. Weak alone, but it is the arm that
  catches a regression to address zero.
- **240 successive 4 KB allocations all succeed and every byte of each is
  written.** This is the `HEAP_ARENA` == `WasmArena` byte-size equality, finally
  asserted rather than inspected: if `HEAP_ARENA` exceeds the buffer, `HeapEnd`
  sits past its end and the writes walk out; if the buffer exceeds `HEAP_ARENA`,
  blocks run out early.
- the 240 blocks span >= 900000 bytes — catches recycling or overlap that
  per-block success would not.
- **a global sentinel survives filling the arena** — this is the actual defect.
  Allocation from address 0 read back correctly for the first kilobyte; "the
  object works" was never evidence. Measured intact after 980856 bytes.

Nothing pins the arena's ADDRESS: it is a BSS-layout accident, and pinning it
would make any unrelated BSS change look like this bug returning. `test/wasm/check_managed.sh` asserted the return is *below* 1024 and so failed by
design when this reached that branch — **and so did `check_calls.sh`, which
carried its own "the heap has no arena" arm that neither of us knew about.** Both
rewritten by that lane to assert properties instead of the defect (`0f9cd8c72`).

### Sizing — 1 MiB, on the lane's own measurement

The backend derives the module's declared page count from `BSSSize`
(`WasmFinishMemory`), so the arena raises `(memory N)` for **every** module with
no backend change, and BSS is never emitted, so the `.wasm` does not grow — the
cost is address space committed at instantiation. hello-world is `(memory 2)` =
128 KiB today; 1 MiB takes it to 18 pages. Multi-MiB would buy headroom nobody is
using at a price every module pays, and the ceiling stops mattering once the
`memory.grow` intrinsic lands.

`WasmArenaBase` is a named function rather than `@WasmArena[0]` inlined, so the
growth arm replaces one expression. Declared **above** its caller: FPC resolves
in source order and the seed build is the only thing that checks.

`memory.grow` remains **not this ticket**, per the body above. Confirmed by the
wasm lane: the module is already declared with the no-maximum limits form, so
growth is legal today and nothing here forecloses it — the missing piece is only
the intrinsic.

### Gate

`make compiler/pascal26` — `converged after 1 round(s)`, fixedpoint
`b2dff2c3cbf9`. `tools/forwardlint.py` clean for this change (its only finding is
the pre-existing `rparser.inc` `RExprRecId` seed break, Track R's, unrelated).

## Log
- 2026-08-29 — resolved, commit 3a7d75f12.

---

## VERIFIED ON HARDWARE-EQUIVALENT 2026-08-29 (frankwasm, branch `wasm` @ `0f9cd8c72`)

The half this lane could not run. All three predictions made from master held:

- **`(memory 18)`** for the probe program — 2 baseline + 16 for the arena, exactly
  what `BSSSize` feeding `WasmFinishMemory` predicts, and the number that
  justifies 1 MiB over "a few MiB".
- **the arm is selected and correct as compiled** — 124/124 bodies lowered,
  allocations bumping 39152, 40160, 41168 at the expected 1008-byte stride.
- **the sentinel survives** — `111 222 333 444 guard` intact after 980856 bytes of
  writes, which is the defect itself finally falsified rather than inferred.

25 checks green, fixedpoint converged, binary `90b089c95cb7`.

**The `-1`-not-`0` call was load-bearing and was nearly lost:** that lane reports
it would have read the `PXX_ESP` arm as the model and copied its `Result := 0`,
not noticing that 0 faults on ESP and is a legal heap address here.
