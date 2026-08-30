---
track: A
type: bug
prio: 55
status: working
found: 2026-08-30
found-by: frankS
owner: frankC
---

# A hidden aggregate-result temp gets a frame slot with NO alignment, and the prologue word-stores into it

`AllocArray('', tyUInt8, 0, bytes - 1)` is how `ir.inc` reserves the caller-side
storage for a call that returns a fixed array (`IRBuildHiddenDest` and
`IRAppendCall`, both guarded by `ProcRetFixedArrBytes[procIdx] > 0`). The
element kind is `tyUInt8`, so `TypeAlign` returns **1**, so
`FrameSize := AlignTo(FrameSize + sz, align)` in `symtab.inc:4151` rounds to
nothing and the slot lands wherever the running frame offset happens to be.

Every backend then **word-accesses that slot**: it is marked
`SymIsHiddenArgTemp`, and each backend's prologue nil-inits it with a 4-byte
store (`s32i` / `sw` / `mov dword`). An odd offset makes that store unaligned.

## Measured — this is not a theory about alignment, it is eight named slots

A probe in the xtensa nil-init loop, on `WriteLn(d)` for a `Double`:

```
XTPROBE unaligned hidden temp: proc=PxxFracDigits   sym=121 name=[] tk=8 isarr=TRUE off=-2729
XTPROBE unaligned hidden temp: proc=PxxFracDigits   sym=122 name=[] tk=8 isarr=TRUE off=-3505
XTPROBE unaligned hidden temp: proc=PxxIntDDigits   sym=114 name=[] tk=8 isarr=TRUE off=-1633
XTPROBE unaligned hidden temp: proc=PxxIntDDigits   sym=115 name=[] tk=8 isarr=TRUE off=-2409
XTPROBE unaligned hidden temp: proc=PxxSciDigits17  sym=117 name=[] tk=8 isarr=TRUE off=-1649
XTPROBE unaligned hidden temp: proc=PxxSciDigits17  sym=118 name=[] tk=8 isarr=TRUE off=-2425
XTPROBE unaligned hidden temp: proc=PxxSciDigits17  sym=119 name=[] tk=8 isarr=TRUE off=-3201
XTPROBE unaligned hidden temp: proc=PxxSciDigits17  sym=120 name=[] tk=8 isarr=TRUE off=-3977
```

`tk=8` is `tyUInt8`, `name=[]` is the unnamed temp, and the eight offsets are
all odd. They sit 776 bytes apart, which is the returned aggregate's size — the
misalignment is introduced once and then inherited by every later slot in the
frame, because nothing re-aligns.

## It is SHARED layout, not one backend's codegen — proved by diffing two backends

Same program, same compiler, xtensa and riscv32, disassembled with the ESP-IDF
toolchain's own `objdump`:

```
xtensa    08074264: movi a8, -1649        riscv32   0807a2e0: li  t0,-1649
          08074267: add  a8, a15, a8                0807a2e4: add t0,s0,t0
          0807426a: movi a9, 0                      0807a2e8: sw  zero,0(t0)
          0807426d: s32i a9, a8, 0
```

**Identical offsets.** So the defect is in the shared allocation, and the six
backends are all emitting an unaligned word store; five of them are simply
never asked to notice. x86-64 and i386 permit unaligned accesses in hardware,
and `qemu-riscv32`/`qemu-arm` emulate them silently in user mode.

## What it costs today, on the one target that traps

Xtensa faults: `SIGBUS {si_code=1 (BUS_ADRALN), si_addr=0x207ff537}` — an odd
address, exactly `a15 - 1649`. The visible symptom is
[[bug-a-xtensa-write-of-any-real-sigbuses-while-str-of-the-same-value-works]]:
**`Write`/`WriteLn` of any real dies**, because the float writers
(`PxxSciDigits17`, `PxxIntDDigits`, `PxxFracDigits`) are precisely the routines
carrying these temps. `Str(d:0:2, s)` of the same value is CORRECT — the
formatting is fine; it is the frame slot.

## Repro

```pascal
program t; var d: Double; begin d := 7; WriteLn('A'); WriteLn('B ', d); end.
```

`--target=xtensa --platform=posix --xtensa-soft-mulhigh`, Call0, qemu-xtensa:
prints `A`, then `B `, then SIGBUS. x86-64 and riscv32 print the number.

A synthetic repro is harder than it looks and I did not find one: the temp is
only nil-inited when `RetType = tyRecord` **and** the record has managed fields
(or the return is a variant), so the ordinary "function returns an odd-sized
fixed array" case allocates the misaligned slot and never word-stores into it.
The natural way in is the real one — build any program that writes a real.

## The fix, and why it belongs to A rather than to the xtensa backend

Making the xtensa nil-init store bytes would hide it: the slot holds an
aggregate that is memcpy'd, field-accessed and (for managed fields) pointer-read
by every backend, so it must be **pointer-aligned**, not merely writable one
byte at a time. Two one-line candidates, both in Track A's files:

- `ir.inc` — allocate the hidden fixed-array temp with an aligned element kind
  (or round `ProcRetFixedArrBytes` up), at both `IRBuildHiddenDest` and
  `IRAppendCall`; **normalise, do not fix one of the two sites**.
- `symtab.inc:4151` — floor the alignment for any hidden aggregate temp, which
  also covers the `AllocVar('', RetType)` arm beside it.

I have deliberately not touched either: `symtab.inc` and `ir.inc` are shared
core and are a Track S stop-line. Filed rather than fixed, per
`CLAUDE.md`'s "shared-internals change → file a Track A ticket".

## The general shape, worth one line in the fix's commit

**An alignment rule enforced only by hardware is not enforced.** Five of six
backends run on machines (or emulators) that permit unaligned word accesses, so
a shared-layout bug that produces them is invisible until the one target that
traps runs the code — and xtensa could not run anything at all until
2026-08-29/30. Same sentence as the four missing-row bugs found the same night:
[[why-xtensa-was-the-holdout]].

## Bound

Object-level plus observable output and a source-level probe, hosted xtensa
profile, Call0, `--xtensa-soft-mulhigh`, at `de8cd038b`; riscv32 comparison
built from the same source by the same compiler. The offsets were read from the
compiler's own symbol table, not inferred from the disassembly. Not checked on
real or emulated ESP silicon, and not checked under the windowed ABI.

## RESOLVED — 2026-08-30 (frankC)

**Fixed in the allocator, as you recommended, but one level more general than
the ticket asked** — and the generality is the argument, not a flourish.

`AllocArray` has five branches. **Four of them already say
`align := TARGET_PTR_SIZE` outright**: dynamic-element, string, frozen string,
and record. Only the scalar branch asks `TypeAlign(elemType)` — the ELEMENT's
alignment — and gets 1 for a byte. So this was never a missing rule; it was one
branch not following a rule the file states four times beside it. The fix is
that branch floored to `TARGET_PTR_SIZE`:

```pascal
align := TypeAlign(elemType);
if align < TARGET_PTR_SIZE then align := TARGET_PTR_SIZE;
```

That covers **both** `ir.inc` sites for free (both reach here through
`AllocArray`), so there is no pair to keep in step — `normalise-dont-special-case`
satisfied by construction rather than by discipline. It also covers every other
byte-array local, which matters because `memcpy` of such a buffer would
word-copy it on the same target that traps.

**`AllocVar` needed nothing**, contrary to the ticket's second candidate:
`TypeSize(tyRecord)` is 8, so `TypeAlign(tyRecord)` is already 8. Checked
rather than assumed, and it is why the fix is one site instead of two.

Cost: **+344 bytes of bss, +52 bytes of code** on the self-hosted compiler.

### Verified by running it, not by inspection

`qemu-xtensa` is present, so the ticket's own repro was run both ways —
the instrument shown capable of failing before its agreement was used:

| | pre-fix | post-fix |
| --- | --- | --- |
| `WriteLn('B ', d)` on xtensa | `A`, `B `, **SIGBUS (signal 7)** | `A`, `B  7.0000000000000000E+000` |
| vs the x86-64 build | — | identical |

- `test/test_write_real_frame_align.pas` added and wired into `test-xtensa`:
  Double, negative Double, Single, and a `:0:3` fixed form. **x86-64 == FPC ==
  xtensa**; the pre-fix compiler SIGBUSes on it.
- Of the three divergences predicted downstream: **`test_cross_float_return`
  and `test_single_in_aggregate` now PASS.** `test_cross_float` no longer
  crashes (it printed nothing at all before) but still differs — see below.
- `make compiler/pascal26` fixedpoint `9ee63ea78bf1`; `tools/gate.sh quick`
  **GREEN**, all six steps.

### What it unmasked — and my first reading of it was wrong

`test_cross_float` runs to completion and still diverges, so I started to
write it up as "xtensa disagrees with the x86-64 oracle". **Then I put FPC
beside both, and the direction reversed:** on those lines x86-64 is the one
that is wrong, and xtensa matches FPC.

| expression | FPC | x86-64 | xtensa |
| --- | --- | --- | --- |
| `s1+s2` (Single op Single) | Single | **Double** | Single |
| `i * s1` | Single | **Double** | Single |
| `i / 2` | Double | Double | **Single** |

Both targets pick float widths for `Write` that FPC does not, in **opposite
directions on different lines**. Filed as
[[bug-a-write-picks-a-different-float-width-per-target-and-both-disagree-with-fpc]]
— explicitly **not** Track F, because a rendering policy cannot be
target-dependent when the frontend is shared: this is width dispatch below the
frontend, and F excludes codegen bugs that merely live in float code.

Two things worth keeping from that:

1. **The x86-64 half has been reachable on every run of the suite since the
   test was written.** `test-xtensa` compares xtensa against the *x86-64
   build*, so the reference cannot be wrong by construction. A
   self-differential's reference is not an oracle.
2. `WriteLn(s)` for a plain `s: Single` agrees across all three. The
   divergence needs the **expression**, not the type — which is why the
   isolated probe I reached for first said everything was fine.

## Log
- 2026-08-30 — filed by frankS with the eight measured slots and the
  two-backend disassembly proving shared layout.
- 2026-08-30 — resolved, commit PENDING-COMMIT.
