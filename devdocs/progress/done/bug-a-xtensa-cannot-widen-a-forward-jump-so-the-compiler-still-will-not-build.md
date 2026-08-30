---
slug: bug-a-xtensa-cannot-widen-a-forward-jump-so-the-compiler-still-will-not-build
track: A+S
prio: 55
type: bug
status: done
found: 2026-08-31
found-by: frankA
owner: "frankA"
blocked-by: []
resolved: dd417a986
summary: "FIXED by relaxation: IREmitMachineCodeXtensa emits the body, and if a three-byte forward slot turned out not to reach, marks that label wide and emits the body AGAIN. Two passes settle every case (the long form reaches +-2 GB); it costs NOTHING below 128 KiB of body, where it never fires. Verified both ABIs against the x64 oracle, with PXXDBG=a.xtrelax:* as the positive control. THE HEADLINE OF THE ORIGINAL SUMMARY WAS WRONG and is corrected here: this was NOT the last wall. The compiler now gets past every jump and stops on the forward CALL instead -- see bug-a-xtensa-cannot-widen-a-forward-call-so-a-big-image-still-refuses-to-build, which is the actual last wall and is re-ranked to 55."
---

# An xtensa forward jump over 128 KiB still cannot be built

Sibling of [[bug-a-xtensa-cannot-widen-a-forward-call-so-a-big-image-still-refuses-to-build]]
— same asymmetry, one level down: that one is CALL0's 512 KiB, this is J's 128 KiB.

## Measured

```
$ compiler/pascal26 --target=xtensa --platform=posix compiler/compiler.pas /tmp/out
pascal26:2922: error: target xtensa: the forward jump at code offset 4040104
  cannot reach its label at 4231481 (J reaches +-128 KiB). A BACKWARD jump this
  far is widened automatically; a forward one cannot be, because the three-byte
  slot was sized before the label existed
```

Reached only after the frame wall
([[bug-a-xtensa-frame-larger-than-32kb-needs-more-than-one-addmi]]) and the
backward half of this one were cleared, so it is what xtensa hits **next**.

## Why the backward half was free and this one is not

A backward jump knows its target when it is emitted, so `EmitXtensaJumpToCode`
picks the form there: everything in range still emits the same three bytes and
only an out-of-reach jump pays ~26. A forward jump reserved three bytes before
the label existed. Widening it means reserving the long form's ~26 bytes at
**every forward jump in every xtensa program** — every `if`, `while` exit and
`case` arm — which is a large size cost on the target where size matters most.
riscv32 took exactly that trade in
[[bug-a-riscv32-cannot-reach-a-far-call-so-the-compiler-will-not-link]] because
there it is 4 bytes against 8. Here it is 3 against 26, and that is the whole
difference.

## The two candidate fixes, neither yet measured

- **Relaxation.** Emit the body, and if any forward fixup is out of range,
  rewind and re-emit with wide slots for those labels only. Free for every
  program that does not need it; the work is that the body's emission also
  appends to `CallFix`, `DynCall`, `IramCallFix` and the relocation lists, so a
  rewind has to restore those counters as well as `CodeLen`. This is the
  standard assembler answer and is probably the right one.
- **A veneer pool.** Patch the 3-byte slot to a short `j` to a long jump
  appended after the body. Cheap, and **does not work here**: the veneer would
  sit past the label, ≥187 KB from the slot, so it is out of J's reach too. Ruled
  out by the same number that reports the bug.

## Not to be confused with

The 3-byte slot is not the only xtensa-specific hazard here: `XtensaAlignCode4`
pads code to 4 and these slots are multiples of 3, so changing a reservation
moves the padding of everything after it (frankS, from the frame work). The
self-host fixedpoint does not see it — the compiler still builds. The cross
differential rows do.

## Gate

`pascal26 --target=xtensa --platform=posix compiler/compiler.pas` must produce an
artifact, plus `make test-xtensa` (every branch in the target goes through the
changed sequence) and the size cost measured with
`tools/count_bytes.py` / `--emit-obj` + `readelf -S`, not the page-quantised
`code=` line.

## Fixed — relaxation, 2026-08-31 by frankA

**The shape.** A forward jump reserves its slot before the label exists, so the
width is a guess and a wrong guess cannot be widened in place — everything after
it would move. So the body is emitted **again**, with the labels that overflowed
marked wide. `XtWideLabel` carries the guess between attempts; a wide slot is the
long form emitted with its `.text`-offset literal left at zero, and the fixup
patches `Patch32(litPos, target - anchorPc)` instead of a three-byte `j`.

Two passes settle it in every case that can occur — the long form reaches ±2 GB,
so the only thing a third could fix is a jump pushed out of range *by* the
widening, which the same loop handles. `XT_MAX_RELAX_PASSES = 4` is a guard, not
a knob.

**It is free below the bound.** The retry fires only when a `j` was *measured*
not to reach, i.e. only in a body over 128 KiB. Measured: `hello` and a 1000-row
generated body do not relax on either ABI; a 3000-row body relaxes in 2 passes
and widens **1 of 2** forward jumps — the near one stays three bytes.

**Why re-emitting is safe, enumerated rather than assumed.** Every table an
xtensa body appends to — `CodeRef`, `Fixups`, `GlobFix`, `CallFix`, `DynCall`,
`IramCallFix` — is a pure `T[Count] := x; Inc(Count)`, so restoring the count
makes the second pass overwrite the first's entries in place. `RegisterExternal`
is idempotent by lookup, the xtensa emitter never touches the data section at
all, and `LibcSyscallCallCount` is x86-64 only. The comment on
`IREmitMachineCodeXtensa` says so, and says what a future table owes it.

**The veneer pool stays rejected** for the reason recorded above: the veneer sits
past the label, ≥187 KB from the slot, out of `J`'s own reach.

## What this cost, and the two instruments that lied

An hour of it was spent on a **regression this ticket's own author had landed
three commits earlier**: `1a4c05d81` loaded the frame size into `a8`, which is
where Call0 leaves the hidden aggregate-result pointer, so every record-returning
function segfaulted. Bisected, fixed and pushed as `cce4a1ffb`. Both tests that
catch it already existed and are already rows in `make test-xtensa`; nothing was
missing but the run.

Then **two instruments disagreed about whether the relaxation had fired**, on the
same program: a raw byte-pattern count of `jx` said 1→2 for windowed and the
objdump mnemonic count said 26→26; for Call0 they swapped which one was right.
Neither is an enumeration, because this backend embeds 4-byte literals in `.text`
and a disassembler resyncs across them. The answer came from asking the emitter.

**And the instrument built to settle it could not fire.** `PXXDBG=a.xtrelax`
printed nothing for four programs, two of which provably relaxed — twice over:
`PxxDbgWants` needs `topic:*` and reads a bare topic as empty, and the
`CurProc >= 0` guard excluded the program **main body**, which is exactly where a
generated repro puts its code. Both now recorded in
`devdocs/dev/debugging-playbook.md`. A silence is not an answer until the channel
has been shown to speak.

## Test

`make test-xtensa` gains a forward row beside frankS's backward one, both ABIs,
with **three** controls: the relaxation must fire once on the generated body on
each ABI, and must NOT fire on `hello` — without that last one the row measures
something that fires everywhere. Pre-fix compiler on the same file:
`j displacement 276001 is outside the encodable range`.
