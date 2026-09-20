---
slug: bug-a-the-bare-esp-profile-cannot-compile-any-nilpy-program
track: A
prio: 55
type: bug
status: new
created: 2026-09-20
found-by: frankS
blocked-by: []
summary: "`tools/esp_run_bare.sh --chip esp32c3 <prog.npy>` fails on EVERY NilPy program tried, including `print(1)`, with three errors inside units the compiler appends itself: `pascal26:1355: error: undefined variable (PXXVarBinOp)`, `pascal26:2029: error: undefined variable (PxxSciDigits17)` and, on a program using str()/concat, `pascal26:193: error: compiler error: PXXRecordRelease not found` in compiler/builtin/promocore.pas. The IDF profile (--platform=esp) compiles the same sources fine, so this is the BARE path specifically. Found 2026-09-20 while trying to build a sensitivity control for [[bug-a-the-nilpy-heap-arena-is-64-kib-of-dead-sram-on-the-esp-idf-profile]], and it BLOCKS that ticket's proof: bare is the only profile where the NilPy heap arena is actually the heap, so it is the only place a deliberately-too-small arena can be shown to fail. The absence is invisible to every tier -- test-esp-bare's fourteen rows are all Pascal, so nothing ever compiles a .npy for bare and the wall generates no red. DIAGNOSED 2026-09-20: the three errors are ONE cause and it is LUMPING, not a missing emission -- builtinheap.pas's {$ifndef PXX_ESP} and {$ifndef PXX_ESP_BARE} blocks each mix a few routines with a genuine bare dependency (a filesystem for PXXStrLoadFile, syscall stdio for the readln block) with ~25 pure pointer/memory routines that have none, and bare loses all of them because they share a guard; the file's own header already says none of the bodies is unimplementable on an ESP chip. BUT FIXING IT DOES NOT BUY A RUNNABLE BARE NilPy PROFILE, which is what this ticket was opened to buy: with every guard neutralised the full demo AND a six-line program both compile completely and stop at CheckBareImageFitsSram, over the stack top by 1,967,792 and 1,958,988 bytes respectively -- an 8,804-byte spread, so ~99.6% of a ~2.2 MB image is fixed NilPy runtime and bare places all of it in SRAM. So SPLIT THE GUARDS ON THEIR OWN MERITS (a bare Pascal program gains the same ~25 routines), and rank the arena control it was supposed to unblock as UNBUYABLE HERE."
---

# The bare ESP profile cannot compile any NilPy program

Measured 2026-09-20, compiler at `c6c5f5f1b`, stock `SocNilPyArenaSize`.

```
$ printf 'print(1)\n' > tiny.npy
$ tools/esp_run_bare.sh --chip esp32c3 tiny.npy
pascal26:1355: error: undefined variable (PXXVarBinOp)
pascal26:2029: error: undefined variable (PxxSciDigits17)
```

With `str()` and string concatenation the program dies earlier still, inside
`compiler/builtin/promocore.pas`:

```
pascal26:193: error: compiler error: PXXRecordRelease not found
```

Every one of these is in a unit **the compiler appends itself** — the
diagnostic says so — so this is not the user program's doing.

## Why nothing caught it

`test-esp-bare`'s rows are Pascal fixtures. **Nothing anywhere compiles a
`.npy` for `--esp-profile=bare`**, so the wall produces no red and no ticket.

**This is a coverage hole that produces SILENCE, which is the shape nobody
finds by watching for reds.** A broken row goes red and someone bisects it; a
row that does not exist generates nothing at all, and the profile reads as
healthy for exactly as long as nobody tries it. It was found only because a
DIFFERENT ticket needed this profile as a control — i.e. by someone walking in
from outside, which is the only way an absence is ever found.

## Why it matters beyond itself

It **blocks the proof** of
[[bug-a-the-nilpy-heap-arena-is-64-kib-of-dead-sram-on-the-esp-idf-profile]].
That ticket's claim is that a 64 KiB arena is dead on IDF, evidenced partly by
a 16-byte arena leaving the demo passing. That evidence is only worth
something if a live 16-byte arena would fail loudly — and **bare is the only
profile where the arena is the heap**, so it is the only place that control can
be run.

It also means the arena constant currently helps nobody: it costs 64 KiB on
the profile that works and serves the profile that does not compile.

## What would retire this

A NilPy program booting under `esp_run_bare.sh` on both chips, and a row in
`test-esp-bare` that compiles a `.npy` — **the absence of which is the actual
defect here**, since the compile wall is a thing anyone could have hit and
nobody did.

## ANSWERED 2026-09-20 — one cause, and a second wall behind it

**Expectation recorded before the probe** (frankz-e5 and frankS independently):
*three errors in units the compiler appends itself smells like one missing
emission rather than three defects, and fixing it buys the control AND the bare
NilPy profile in one go.* **Half right.** One cause, yes. The profile, no.

### The cause is one guard doing two jobs, three times over

`builtinheap.pas:18` reads `{$ifdef PXX_ESP_BARE}{$define PXX_ESP}{$endif}`, so
bare inherits every `{$ifndef PXX_ESP}` exclusion in the file. Those blocks are
not lists of things an ESP chip cannot do — the unit's own header says so in as
many words, *"none of these bodies is unimplementable on an ESP chip... Do not
read the list as 'ESP cannot do this'"*. Each block contains a small genuine
core and a large lumped remainder:

| block | genuine bare dependency | lumped in beside it |
| --- | --- | --- |
| `{$ifndef PXX_ESP}` 553-598 | `PXXStrLoadFile` (needs a filesystem) | the whole record/dynarray retain-release walk, the variant runtime, `PxxSciDigits17` |
| `{$ifndef PXX_ESP_BARE}` 2944-3312 | console read/write over `PXXSysWrite` | `PXXCStrToFrozen`, which is a bounded `memcpy` with a length prefix |

All three reported errors are that: `PXXVarBinOp`, `PxxSciDigits17` and
`PXXRecordRelease` are pure pointer code excluded because they share a guard
with a filesystem routine. Clearing the marker walks the build straight to the
next lumped name (`PXXCStrToFrozen`) and then off the end of the stack
entirely.

**One genuine dependency did turn up and it is not lumping:** the float bodies
need softfloat, and `PullSoftFloatBeforeBuiltinHeap` deliberately skips bare so
a float-free MCU program does not pay ~54-64 KB of flash. That reasoning does
not transfer to NilPy, where every number is a float — so a bare NilPy build
must pull softfloat, and a bare Pascal build must keep not doing so.

### The wall behind it is size, and it is not close

With the markers neutralised and softfloat pulled, **the program compiles** —
all the way to `CheckBareImageFitsSram`. Compiler `f18adc62d2ac`, `esp32c3`:

| program | `--dce` | `--no-dce` |
| --- | --- | --- |
| the full nilpy-c3 demo | over by **1,967,792 B** | — |
| a six-line `while`/`append` program | over by **1,958,988 B** | over by 2,815,572 B |

**The six-line program is within 8,804 bytes of the full demo**, so ~99.6% of
the image is fixed NilPy runtime, and bare has no flash mapping — the whole
image lives in SRAM. Over by ~1.9 MB against a window of a few hundred KiB is
not a DCE problem: DCE is **on by default here** and already removes 856,584 B
(`--no-dce` minus `--dce`, matching `dce: code 2906044B -> 2049456B` to within
4 bytes of the report).

*That A/B is also a retraction: a first pass compared no-flag against `--dce`,
got byte-identical addresses, and I began writing up "a pass reports a drop the
image does not show". The flag was already on. `--no-dce` is the control that
existed the whole time.*

### What to do with this

1. **Split the guards on their own merits.** A bare *Pascal* program gains the
   same ~25 routines — managed records, dynarrays, variants — and that is worth
   doing whether or not NilPy ever fits. File as its own item; it is not this
   ticket's original goal.
2. **Do not rank this as the arena control's blocker any more.** The control is
   unbuyable on bare for NilPy at any plausible runtime size. The arena question
   was settled another way — see
   [[bug-a-the-nilpy-heap-arena-is-64-kib-of-dead-sram-on-the-esp-idf-profile]],
   which now proves the arena dead by REACHABILITY (`HeapMmap` survives
   `--no-dce` and is dropped by `--dce`) instead of by survival.
3. **What would retire the size row:** a bare profile that maps code from flash,
   or a NilPy runtime an order of magnitude smaller. Re-run the two-row table.
