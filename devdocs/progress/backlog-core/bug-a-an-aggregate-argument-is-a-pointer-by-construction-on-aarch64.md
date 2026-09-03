---
track: A
prio: 45
type: bug
found: 2026-09-01
found-by: frankC
summary: "aarch64 is the last target where a by-value aggregate argument occupies one pointer-sized slot by CONSTRUCTION rather than by classification: ABIA64CdeclArgSlot advances the NSAA by a fixed 8 bytes per argument, so an aggregate of any size gets exactly one slot and its three readers inherit that. x86-64 and i386 were converted by bug-a-c-a-by-value-struct-parameter-is-passed-as-a-pointer-to-every-c-abi-callee. THE ORACLE CLAUSE THIS TICKET WAS FILED WITH IS FALSE AND IS CORRECTED BELOW (2026-09-03): there is no cross gcc and no mixed LINK, but `clang --target=aarch64-linux-gnu -S` is a placement oracle that needs nothing installed and reads the CALL SITE, and llvm-objdump-21 reads pxx's own aarch64 ELF for the other column. MEASURED against it, five by-value shapes in one program: pxx emits `x0 = &temp, x1 = tail` for ALL FIVE, while AAPCS64 wants `{int,int}` packed in x0, `{long,long}` in x0+x1, a 24-byte struct indirect, `{double,double}` in d0+d1 and `{float,float,float}` in s0..s2 -- and after an HFA the tail integer goes to w0, because the banks allocate independently. FOUR OF FIVE ROWS WRONG AND THE FIFTH RIGHT BY ACCIDENT: a 24-byte struct really is indirect, so the always-a-pointer construction collides with the psABI on exactly the shape a single hand-written probe would choose. Work is now the classifier, not the oracle. Remaining gap: this is a PLACEMENT oracle and never runs, and the outcome oracle on aarch64 (a dynamic call into the target's glibc) cannot reach this ticket because no libc entry point takes a large aggregate by value."
---

# An aggregate argument is a pointer by construction on aarch64

`ABIA64CdeclArgSlot` (`compiler/abi.inc:521`) advances the next-stacked-argument
address by a fixed 8 per argument. AAPCS64 wants an aggregate <= 16 bytes in
one or two consecutive X registers, an aggregate of 1-4 identical float members
(an HFA) in that many V registers, and anything larger passed by reference to a
caller-made copy — the *caller* copies, and that indirection is part of the ABI
rather than a shortcut.

Readers, all inheriting the one-slot assumption:

| file | line | arm |
| --- | --- | --- |
| `ir_codegen.inc` | 1538 | callee spill |
| `ir_codegen_aarch64.inc` | 3443, 3454 | direct call |
| `ir_codegen_aarch64.inc` | 3630, 3641 | indirect call |

That is the same three-arm shape x86-64 and i386 had, and the same trap: fixing
the direct arm and not the indirect one produces a gate that passes because the
subject contains no call through a function pointer.

## THE FIRST DELIVERABLE IS AN ORACLE

**Do not start with the classifier.** The parent ticket's entire finding is that
a calling convention cannot be judged from inside one implementation: pxx agreed
with itself about passing a struct as a pointer for as long as the code existed,
and every test passed. On x86-64 and i386 the disagreement became visible only
when a gcc-compiled `main` was linked against a pxx-compiled object and the
fields were read across the boundary.

**No such link is constructible here.** Measured 2026-09-01: no
`aarch64-linux-gnu-gcc`, and the same for arm32 and riscv32. Options, cheapest
first:

1. **A cross toolchain.** `gcc-aarch64-linux-gnu` + `qemu-aarch64`, both already
   depended on elsewhere in this tree for the cross test rungs. Installing is
   the owner's call (it leaves this machine). This is the one that makes the
   fix ordinary work.
2. **A hand-written assembly caller**, assembled by pxx's own aarch64 backend
   from the AAPCS64 document. It tests the reading of the document, not
   agreement with the platform — genuinely weaker, but not worthless, and it is
   what `test-c-abi-glibc-oracle` does in spirit.
3. **A glibc entry point taking a struct by value**, under qemu. The parent
   ticket already looked: the routines this corpus calls take scalars and
   varargs, so the substitute oracle does not extend.

## Why it is not urgent

Nothing reaches it today. aarch64 has no stack argument passing for the three
C-ABI call kinds at all
([[bug-a-aarch64-has-no-stack-argument-passing-for-the-three-c-abi-call-kinds]]),
so a program that would expose the NSAA advance mostly fails earlier and more
loudly. **That is a reason to sequence the two, not a reason to defer both** —
and it is worth noticing that the louder bug is protecting the quieter one from
being observed.

Split out of [[bug-a-c-a-by-value-struct-parameter-is-passed-as-a-pointer-to-every-c-abi-callee]]
when that closed for x86-64 and i386.
# 2026-09-03 — WHAT THE MISSING ORACLE ACTUALLY NEEDS, measured

This ticket and `bug-a-an-aggregate-argument-is-a-pointer-by-construction-on-aarch64`
both say the first deliverable is an oracle and neither says what is missing.
Measured on plexus so the next reader does not re-derive it. A mixed link needs
three pieces; **two of them are already here.**

| piece | aarch64 / arm32 / riscv32 | how checked |
| --- | --- | --- |
| a foreign C compiler that emits an object | **PRESENT** — clang 21.1.8 | `clang --target=aarch64-linux-gnu -c` produces `ELF 64-bit LSB relocatable, ARM aarch64` with **no sysroot and no headers**, which is all an ABI probe needs |
| a runner | **PRESENT** — `qemu-aarch64`, `qemu-arm`, and the rest under `/usr/bin/qemu-*` | `tools/run_target.sh` already uses them |
| a LINKER for those architectures | **ABSENT** | `ld -V` lists only `elf_x86_64 elf_i386 elf32_x86_64 elf_iamcu i386pep i386pe`; no `ld.lld`, no `*-linux-gnu-gcc` of any flavour |

**So the blocker is one tool, not a toolchain.** That is worth stating precisely
because "we need a cross toolchain" reads as an expensive ask and is the reason
this has sat: the compiler and the runner are installed, and what is missing is
the thing in the middle.

Two routes neither of which works today, both checked rather than assumed:

- **pxx links it.** pxx writes aarch64 executables already, so it has the ELF
  writer. It cannot consume a foreign object: `pascal26 foo.o out` answers
  `error: unexpected character` — object files are not an accepted input, and
  `--emit-obj` itself lists **"general objects: x86-64, i386, xtensa, riscv32"**,
  so aarch64 and arm32 cannot even be emitted (that is
  `feature-a-object-output-for-arm32-and-aarch64`, p45, and it is a genuine
  second blocker for the pxx-emits/foreign-links direction — but NOT for the
  clang-emits/something-links direction, which needs only the linker).
- **GNU ld with an emulation flag.** `ld -m aarch64linux` is rejected; this
  binutils is not the multiarch build.

**What I did NOT verify, stated as the unmeasured half:** that `lld` (or
`binutils-multiarch`) would in fact close it. It is the obvious candidate and I
could not test it because it is not installed, and installing it is an apt
operation — the owner's, not an agent's. Everything above IS measured.

So the actionable form of "this needs an oracle first" is: **ask the owner for a
linker that targets aarch64/arm32/riscv32, and the rest of the rig is buildable
from parts already on the box.** `test-c-abi-mixed-link` is already written to
skip a target it cannot build and to go RED if every target skips, so extending
its target list costs nothing until the linker exists.
**CORRECTION, same day, to the note above.** It concludes that the missing piece
is a LINKER. That is true of a static mixed LINK and it is not the answer to "is
there an oracle", because **a mixed CALL is enough and it already works**:
`~/.cache/pxx-cross/{aarch64,arm32}/lib/` holds a complete glibc that
`run_target.sh` already puts on `QEMU_LD_PREFIX`, pxx already emits dynamic
imports for those targets, and a pxx caller into gcc-built glibc is a real ABI
boundary with the callee's own output as the observable. Worked instance, found
that way within the hour:
`bug-a-aarch64-passes-a-variadic-float-in-an-fp-register-so-glibc-reads-zero`
— `[0.00]` against arm32's and x86-64's `[3.50]`, where the pxx-vs-pxx version of
the same program is self-consistently wrong. Read that ticket's ORACLE section
before concluding this one is blocked. The linker is still needed for the other
direction (a pxx-compiled CALLEE receiving from gcc-compiled code), and riscv32
and xtensa are covered by neither — both refuse dynamic symbols outright.

# 2026-09-03 (frankB) — THE ORACLE EXISTS. The premise above is wrong, and the defect is now measured against it

This ticket's summary says *"there is no gcc cross for aarch64 on this box, so
no mixed link is constructible and the only available verification is
pxx-against-pxx"*. **The clause about a LINK is true and the conclusion about an
ORACLE is false.** `clang` is a cross compiler by construction and needs nothing
installed:

```
clang --target=aarch64-linux-gnu -O1 -S -o - probe.c
```

Declare the callees `extern` and never define them — you are reading the CALL
SITE, so nothing links and nothing runs. `llvm-objdump-21` (installed) reads
pxx's own aarch64 ELF for the other column. Full method, and the arm32/riscv32
rows, in `devdocs/dev/differential-probes.md`, "A CROSS-TARGET ABI ORACLE EXISTS
ON THIS BOX, AND IT IS NOT A CROSS GCC".

## Measured, five shapes, one program, aarch64

Each call takes the aggregate by value plus a distinct integer tail, which is
what makes the SLOT COUNT visible and not just the bytes:

| shape | size | clang (AAPCS64) | pxx today |
| --- | --- | --- | --- |
| `struct {int a, b;}` | 8 | `x0` packed, tail `w1` | `x0 = &tmp`, tail `x1` |
| `struct {long a, b;}` | 16 | `x0, x1`, tail `w2` | `x0 = &tmp`, tail `x1` |
| `struct {long a, b, c;}` | 24 | POINTER `x0`, tail `w1` | `x0 = &tmp`, tail `x1` |
| `struct {double x, y;}` (HFA) | 16 | `d0, d1`, tail `w0` | `x0 = &tmp`, tail `x1` |
| `struct {float x, y, z;}` (HFA) | 12 | `s0, s1, s2`, tail `w0` | `x0 = &tmp`, tail `x1` |

pxx emits `memcpy` to a 16-byte temp and then `x0 = &temp` for **every** row —
one pointer slot by construction, exactly as the ticket says.

**FOUR OF FIVE ROWS ARE WRONG AND THE FIFTH IS RIGHT BY ACCIDENT.** A 24-byte
struct really does go indirectly on AAPCS64, so "always a pointer" happens to be
correct there — and a big struct is precisely the shape a single hand-written
probe would use. This is CLAUDE.md's "choose a probe whose right answer differs
from the default" seen from the other side: the bug's answer collides with the
psABI on the one case most likely to be tested. Any probe for this must vary
SIZE and MEMBER TYPE.

Note the third column of the clang rows: after an HFA the tail integer lands in
`w0`, because the GP and FP banks allocate independently. A fix that puts an HFA
in `d0,d1` but keeps advancing the GP index will place the tail in `w2` and be
wrong in a way no single-argument probe can see.

## What this unblocks and what it does not

The oracle is here, so the "first deliverable is an oracle" clause is discharged
and the work is now the classifier itself: `ABIA64CdeclArgSlot` advancing a fixed
8 per argument has to become an AAPCS64 aggregate classification (HFA of 1-4
identical FP members → that many FP registers; aggregate <= 16 bytes → one or two
X registers; larger → indirect, one slot), and its three readers inherit it.

**It is a PLACEMENT oracle, not an OUTCOME one.** It reads the call site and
never runs, so it cannot catch a placement that is right and read back wrong. The
running-program oracle on this target is the glibc dynamic call, and it cannot
reach this ticket at all, because no libc entry point takes a large aggregate by
value. Both halves are needed and neither substitutes for the other.

## Step 1 of 2, landed: the classifier, proven before anything reads it

`ABIA64RecordClass` in `abi.inc` answers the AAPCS64 question for a by-value
composite:

- **HFA first, because it is not a size question.** `{double,double}` and
  `{long,long}` are both 16 bytes and go to different banks; only the member
  types separate them. `ABIA64WalkHfa` flattens nested records and static arrays
  and requires every member to be the SAME fundamental FP type, at most four of
  them, with `size = count * TypeSlotSize` so padding cannot masquerade as
  homogeneity.
- otherwise `size <= 16` → 1 or 2 X registers holding the aggregate's own bytes,
- otherwise **indirect** — one GP slot holding a pointer.
- and it REFUSES (`-1`) rather than guessing on: alignment > 8 (AAPCS64 rounds
  NGRN up to an even number for a 16-aligned composite and that is not modelled
  yet, so an answer would place the argument one register early), an unknown
  size, `tyExtended` (pxx's is 8 bytes and C's `long double` is 16 on this ABI —
  the same refusal `ABISysVMergeScalar` makes, for the same reason), a dynamic
  array member, or a builtin record id.

**It has no production consumer yet, deliberately.** `PXXDBG=a.a64cls` prints it
per C record parameter — the exact shape `a.sysvcls` already has for SysV, whose
own comment says the point is that the classifier can be checked against an
oracle *before any codegen is built on it, rather than debugging the classifier
and the marshalling at the same time*. `test/caarch64_aggregate_class.c` asserts
eleven shapes in `make test-core`.

Every asserted row disagrees with what the compiler currently does. A classifier
that did nothing would print `REFUSE` on all eleven, so the guard cannot pass on
an inert one.

### Verified against clang, row by row — and the .expected's provenance

The `.expected` was PRODUCED by the probe and then CHECKED against
`clang --target=aarch64-linux-gnu -O1 -S`; it is not a transcript of clang's
output, and the test says so, because claiming otherwise would be the same error
as writing today's answer into a `.expected` and calling it an oracle.

Tail-argument register per shape (which names how many slots of each bank the
aggregate ahead of it consumed), clang 21.1.8:

| shape | size | clang tail | classifier |
| --- | --- | --- | --- |
| `{int}` | 4 | `w1` | 1 GP |
| `{int,int}` | 8 | `w1` | 1 GP |
| `{int,int,int}` | 12 | `w2` | 2 GP |
| `{long,long}` | 16 | `w2` | 2 GP |
| `{long,long,long}` | 24 | `w1` + `mov x0, sp` | INDIRECT |
| `{double}` | 8 | `w0` | HFA 1 x double |
| `{double,double}` | 16 | `w0` | HFA 2 x double |
| `{float,float,float}` | 12 | `w0` | HFA 3 x single |
| `{float,float,float,float}` | 16 | `w0` | HFA 4 x single |
| `{float x5}` | 20 | `w1` + `mov x0, sp` | INDIRECT |
| `{double,int}` | 16 | `w2` | 2 GP |

`hfa5` is the row that shows the member LIMIT is four and not the size, and
`mix` is 16 bytes with a double first and still not an HFA.

## Step 2, and the two facts it must not lose

The by-value switch is `ABICRecordParamByValue`, which returns False for aarch64
today, so a C record parameter is marked `IsRef` and both sides agree on a
pointer. **Flipping it moves the caller and the callee at once, because it is one
decision** — the variadic-float attempt on this same target proved what a
caller-only half does, and that lesson is one commit old.

Two placement facts measured from the same oracle that classification does not
model and step 2 must:

1. **An HFA that does not fit the remaining FP bank goes to the stack ENTIRELY.**
   Five `{double,double}` arguments put four in `d0..d7` and the fifth wholly on
   the stack. Same all-or-nothing rule `ABISysVArgPlace` states for SysV, and the
   same failure if restated per slot: the first half placed, the second stranded.
2. **The banks allocate independently, so the tail integer after an HFA lands in
   `w0`.** A fix that places the HFA in `d0,d1` and still advances the GP index
   puts that tail in `w2` — wrong in a way NO SINGLE-ARGUMENT PROBE CAN SEE.
   Every probe for step 2 needs a trailing scalar.
