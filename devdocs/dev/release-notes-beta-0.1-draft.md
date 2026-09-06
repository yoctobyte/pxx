# pxx / pascal26 — beta 0.1

**Draft for review. Not published.**

An arbitrary point in a long piece of work. There is a real backlog, some of it
in this document. There is also a compiler that compiles real programs for seven
targets and rebuilds itself byte-for-byte, and it is about time somebody could
try it.

Everything below was measured against the pinned build **v406**, commit
`ab72ab352`, compiler binary sha256 `4bfd73d70588`.

---

## What it is

A self-hosting compiler for a Pascal dialect, seeded from FPC, with its own
runtime library, its own ELF writer, seven code generators, and four additional
language frontends sharing one AST and one IR.

The goal is **languages × platforms** — every frontend on every target. That is
the goal, not the state. This release is a snapshot of how far along it is.

`pascal26` reproduces itself exactly: compiled by itself, it emits a
byte-identical binary. That is the strongest single guarantee here and also a
narrow one — it says the compiler is self-consistent at the default optimisation
level. **It does not say the compiler is correct**, and for the C, Python, Rust
and Zig frontends it says nothing at all, because `compiler.pas` is Pascal.

## Targets

`x86-64` (default), `i386`, `aarch64`, `arm32`, `riscv32`, `xtensa`, `wasm32`.

The same six-line program, compiled by the pinned build and run under emulation:

```pascal
begin writeln(6*7) end.
```

```
native    42
i386      42
aarch64   42
arm32     42
riscv32   42
```

and in C, through the same compiler:

```c
#include <stdio.h>
int main(void) { printf("%d\n", 6*7); return 0; }
```

```
native    42
i386      42
aarch64   42
arm32     42
riscv32   42
```

The same five targets, in both languages, through the same pinned compiler.
That is the complete runnable set, not a sample of it.

**xtensa is an ESP target and ESP is not a Unix.** 33 platform-layer entries
refuse deliberately rather than returning a plausible wrong answer — FreeRTOS
gives you tasks, not processes, and POSIX-shaped code meets a clear refusal
instead of silence. That is a design decision, not a gap.

**On ESP, Pascal is the only frontend that gets there.** Measured, one
hello-world per frontend across four ESP configurations: Pascal runs, backed by
31 executed emulator assertions. C reaches none of the four; on one
configuration it refuses cleanly, but only when asked for a standalone
executable, which is not how C ships to this target — the clean refusal is a
property of the **output mode**, not of the chip. Nil-Python, Zig and Rust
refuse on all four — mostly honestly, saying that a heap arena needs `mmap`, or that the
skeleton supports x86-64 only. Those are frontends working correctly in cells
nobody has built out yet, not twelve failures. But **"all frontends" is not a
sentence that belongs anywhere near the ESP story**, and only the Pascal row
means *runs*: a future row that merely compiles is a different claim and needs a
different word.

**wasm32 is real but unwired.** Its two test suites are green and both are run
by hand — no continuous tier covers it, so it carries less evidence than the
other six. It is also where the honest caveat lives, and the caveat got sharper
between the first draft of this file and the pin. **Three separate wasm32-only
defects were found while the suites were fully green**, all three silent:

- a `Variant` written through a pointer put its payload over its own tag,
  giving 42 natively and 0 on wasm32 — fixed, and that fix is in this pin;
- every Nil-Python object bound to a local leaked, once per call, on wasm32 and
  no other target. It corrupts nothing, so every value assertion in the suite
  passed on both sides of it: measured 1900 objects stranded at 2000 iterations
  and 7815 at 8000, against a flat 1 on x86-64 for the same source;
- a managed local a generator held **across a yield** was released at the yield,
  so the generator resumed holding a dead handle — six lines of Nil-Python
  printing `4 5` on x86-64 and `4 2` on wasm32, no crash and no diagnostic.

The last two are fixed on master and are **not in this pin**. All three were
green under both suites the whole time they were live, and the reason is the
same each time: wasm32 has its own copy of machinery the other six targets
share, so a row missing there is missing on exactly the target nobody measures.
**A green suite is evidence about what it tests**, and on this target that
sentence has now been paid for three times.

## What it compiles

The compiler itself. zlib, matching the gcc oracle on the program's **output**
— verified against the pinned compiler this release ships, not only against a
development build. That check skips itself, quietly and green, on a machine
without `gcc` or without the zlib source: it is the "skips it knows about"
category below, applied to one of the two claims on this page.

A chess perft. All **36 of 36** host demo programs build against this pin —
adventure games, a TUI, a bignum library, a small VM. The 9 `examples/esp32/`
demos are cross-only and are not built here.

## Optimisation

`-O0` through `-O3`. `-O2` is the default and the proven one; `-O3` is
experimental. **`-O4` does not exist** — the compiler answers `unknown option`.
If you see it named anywhere, that is a document being aspirational.

---

# Limitations

Written per frontend, and only where somebody measured it. A beta is allowed a
backlog of things that *refuse* — you get a diagnostic and can work around it.
The list worth your attention is the shorter one: things that compile, run, and
are quietly wrong.

## C

Four known limitations. **One of them tells you.**

**`setvbuf` returns success and does nothing.** It discards all four arguments
and returns 0, which C99 defines as success. This is first on the list because
it is the only one that *punishes* care: the programmer who correctly checks the
return value is the one who is misled. There is no defensive style that helps.

**`long double` is 8 bytes; gcc's is 16.** `sizeof(long double)` and
`sizeof(struct { long double x; })` are both 16 under gcc and both 8 here, from
the same source, with no diagnostic. A single translation unit is
self-consistent; an aggregate containing one disagrees about its own size the
moment it crosses a boundary into gcc-compiled code — `struct { char c; long
double y; }` is **32 under gcc and 16 here**, which is a shape real C writes.
That struct row is also the one to test with: pxx's 8 for the bare type is
equally `sizeof(double)`, so on its own it cannot separate "modelled as double"
from "unrecognised and defaulted". The struct can.

**`__thread` and `_Thread_local` are ignored — but they now warn.** Every thread
shares one copy of a variable declared per-thread; the object contains no
`.tbss` or `.tdata` section at all. Since this pin the compiler says so, once
per compilation. It is the only one of the four you can discover from a message.
Pascal takes the other road and *refuses* `threadvar` outright.

**An internal integer-formatting helper has an unbounded loop** on a base value
no ordinary program supplies. Listed for completeness; it is parked deliberately
as a diagnostic aid for a defect not yet identified.

The current set is derived, not transcribed — these queries are the list:

```sh
grep -rl '^## RELEASE-RISK: SILENT-WRONG' devdocs/progress/
grep -rl '^## RELEASE-RISK: DIAGNOSED'    devdocs/progress/
```

C on wasm32 is **freestanding only**. `int main(void){return 42;}` builds and
exits 42, `void main` runs, and `argc`/`argv` arrive correctly through WASI —
the entry point is synthesised as an exported `_start`, since a wasm module has
no code offset 0 to hand-assemble one at.

Anything reaching for `<stdio.h>` still refuses, and **the refusal no longer
reads as well as it did.** It used to name `environ`; that wall was removed, and
what stands behind it is the C runtime library itself failing to compile for
this target — one row hits an internal limit on locals per function, another
hits the missing wasm32 `va_arg`. Both name the crtl file they come from, so you
can tell it is our runtime rather than your program, but neither is a sentence
written for a C author. That is a real regression in message quality, taken
deliberately in exchange for the diagnostic being about the true obstacle: the
old one named a wall that was not the wall.

## Pascal

FPC and Delphi modes, and explicitly not every dialect of either. We do not
chase FPC bug-for-bug; we care that correct Pascal compiles correctly.

One alias-resolution defect is fixed in this pin. A census settled its scope:
**exactly one affected name in everything pxx ships — `IUnknown`, and that one
failed loudly** — because the alias table only ever admitted class types, so a
scalar alias such as `HResult = LongInt` was never a candidate. **Loudly is a
property of that instance and not of the defect**: where the two targets happen
to be compatible, the same mechanism bound the wrong type with no diagnostic at
all. **A dynamic array of a class type loses its element type when passed as a
parameter.** Reading elements gives wrong values with no diagnostic; `var` and
open-array spellings read out of bounds. Arrays of records and of scalars are
unaffected, as are globals. `array of TSomeClass` as a parameter is an everyday
shape and the by-value face is silent, which puts it in the first category this
document cares about. Pre-existing, not introduced by this pin. Fix in progress.

What remains genuinely **unmeasured** is third-party Pascal that declares a
class or interface alias re-using a builtin name — and that is the shape the
silent face fits, so the sentence above is not reassurance about it. Unmeasured
is the accurate word; it is not a claim that the case is fine.

## Nil-Python

**A four-target frontend**: x86-64, i386, aarch64 and arm32. It refuses
riscv32, naming its own ticket. Its only other appearance beside a target on
this page is inside the ESP paragraph, grouped with Rust and Zig — true of ESP,
and not true generally.

Upward compatible with CPython, in one direction only: a program CPython accepts
must behave the same here. Accepting **more** than CPython is deliberate and is
not a bug. The deliberate divergences are written down in
`devdocs/dev/nilpy-semantics-divergences.md`; anything differing that is *not*
in that file is a bug and we want to hear about it.

## Rust and Zig

Work in progress, and mentioned only so their presence in the tree is not
mistaken for a claim. Both are early — a handful of tests on one target each,
against thousands on fourteen for Pascal. Do not plan around them.

The one-target limit is a **refusal, not an untested gap**: disable it and both
frontends compile clean for i386, aarch64 and arm32, and every binary dies
before its first syscall on a literal x86-64 tail three skeleton drivers emit
unconditionally. They refuse rather than emit something that would not run —
the same virtue credited in the ESP paragraph above.

## One compiler-wide defect worth knowing before you script anything

**A successful-looking compile does not currently prove an output file exists.**

```
$ pascal26 hello.pas /nonexistent-dir/out
ok: /nonexistent-dir/out  [code=65304B  data=2792B  bss=43524B  procs=136]
$ echo $?
0
```

No file was written. The verb, the byte counts and the exit status all come from
the in-memory image; none is checked against the filesystem. If you drive
`pascal26` from a build script, test for the artefact rather than trusting the
exit code. Filed, and not fixed in this pin.

---

# How much of this is tested

Worth stating plainly, because "the suite is green" is a weaker sentence than it
sounds and we would rather you knew the shape of it.

Continuous testing reports **failures** and **skips-it-knows-about**, and both
are counted. Two further categories are not:

- **Test arms that skip themselves**, which decline for reasons of their own.
  These are recorded and named, but deliberately not counted as coverage holes:
  a recipe that guards itself out is making a judgement the harness does not get
  to overrule. A skipped job is still a job that did not run.
- **Whole suites in no tier at all** — wasm32 and two ESP **suites**
  (`test-esp-bare`, `test-esp-softfloat`). Not a failure, not a skip, not
  counted anywhere. An absence no number reports — and, for the ESP pair, an
  absence with a **named cause** rather than an oversight: stock qemu has no
  ESP32 machine at either ISA, so they cannot be enrolled anywhere until the
  Espressif toolchain is on the runner.

So a green run is real evidence about the first two categories and silent about
the last one.

**A concrete case, because it is the honest shape of the problem.** A block of
riscv32 test rows was skipped behind one shared sentence — *"backend feature
gap"* — written in a single commit in July and never revisited. As of this
release **every one of them has been measured, individually.** The sentence was
true of two.

Twenty-two build, run, and match the x86-64 oracle byte for byte. Two refuse
for real, with a diagnostic. One cannot have a cross-target oracle at all — it
prints raw addresses and an instance size that are *supposed* to differ per
target — so its skip was right and its stated reason was wrong. And one **hung
forever**: a timer test on a target lacking `timerfd_settime`, where the error
was assigned to a variable nothing read, handing the caller a timer that never
fires. That row is fixed and now runs. No row still carries the old sentence.

**Those twenty-two are measured, not wired.** Nothing enforces them yet, and
measured-good is not coverage — which is the condition that let the hang sit
there in the first place. Three rows are wired back in; the rest now carry
per-row reasons instead of one shared line.

We are reporting this rather than quietly fixing it, because the failure was
not the hang — it was that **a skip is silent**. A red is loud and gets read. A
skip that sounds settled stops the recount, and one boilerplate line inherited
by a whole block of rows is how a hang sat behind a sentence claiming the
situation was understood. The `test_rtti` row is the sharpest version: the skip
was right and the reason was wrong, which is the worst combination, because
nobody re-checks a row whose reason sounds settled.

Our cross-target C vararg check, for instance, reports **6 built,
1 refused, 7 examined** rather than "pass" — deliberately, because an earlier
version of it recorded a target as *legitimately excluded* when that target
could in fact build and pass. It was green for a day. Carrying the denominator
is what caught it.

---

## Reporting

Bugs, and especially anything in the "compiles and is wrong" shape, are the most
useful thing you can send. Something that refuses with a clear message is
already on a list; something that runs and lies is not.

Beta 0.1. There is a backlog and this document names part of it. The compiler
does real work.
