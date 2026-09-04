---
slug: bug-a-c-the-variadic-struct-abi-is-still-a-pointer-on-aarch64-arm32-and-riscv32
title: "A struct through `...` is still a POINTER on aarch64, arm32 and riscv32"
track: A
prio: 40
type: bug
status: working
created: 2026-09-02
found-by: frankA
owner: frankb-78
blocked-by: []
summary: "The remaining three targets of bug-a-c-a-struct-through-the-variadic-tail-is-passed-as-a-pointer, which was fixed on x86-64 and i386 2026-09-02. A struct or union in a variadic slot still occupies one pointer-width slot holding the address of a caller temp; gcc puts the aggregate's own bytes there. Self-consistent inside pxx, so no pxx-vs-pxx test can see it. Measured unchanged rather than regressed: arm32 and riscv32 print byte-identical output before and after that fix, aarch64 differs only in the garbage stack addresses the broken rows were already printing. THE 'NO ORACLE ON THESE THREE' CLAUSE IS CORRECTED BELOW (2026-09-03): the mixed LINK really is unbuildable (no cross gcc, no lld), but `clang --target=... -S` compiles for all three with nothing installed and reading the CALL SITE needs neither a link nor a run, with llvm-objdump-21 for pxx's column. Three measured facts that change what a fix must do: arm32 NEVER goes indirect (a 12-byte aggregate is r0,r1,r2 with the tail in r3, so the pointer is wrong there at every size); riscv32 DOES at 2x XLEN, so its current pointer is CORRECT for a 12-byte struct and wrong for smaller ones; and riscv32 takes {double,double} in fa0,fa1 but {float,float,float} indirectly, so the FP-struct rule does not port from aarch64. Also `long` is 4 bytes on both 32-bit targets, so size probes in explicit widths. THE FULL PLACEMENT TABLE FOR ALL THREE TARGETS IS NOW MEASURED AND IN THE BODY (2026-09-04), and it changes the shape of the work again: aarch64's VARIADIC rule is its FIXED rule unchanged, HFAs included ({double,double} still goes in d0,d1 on AArch64 Linux, unlike Apple's variant), so that half is exactly "make the tail ask ABIA64ArgDesc"; arm32 SPLITS one aggregate between r1-r3 and the stack, which AAPCS64 never does, so a marshaller ported from the aarch64 one places the head and strands the tail; and riscv32's VARIADIC rule is NOT its fixed rule -- everything over 2x XLEN is a pointer there including {double,double}, which the fixed-parameter row above records as fa0,fa1. Three targets, three rules, two of them differing from that same target's fixed-parameter rule. The mechanism and all three sites are documented on the parent."
---

# The variadic struct ABI on the three cross targets

The parent —
[[bug-a-c-a-struct-through-the-variadic-tail-is-passed-as-a-pointer]] — has the
full mechanism, the three sites and the fix that landed for x86-64 and i386.
This ticket is only what was deliberately left.

## What is already done and carries over

- **`IRLowerCallArg` stamps the record identity** on the argument's value node
  (`IRArgRecId`, `compiler/ir.inc`). That is target-independent and is already
  in place: these three backends can read it today.
- **The receiving half is per-target.** x86-64 materialises a temp and calls
  `__pxx_va_arg_agg`; i386 steps the walk by `RecSize` and derefs once.
  `cparser.inc`'s `__builtin_va_arg` keeps the two-deref path for exactly these
  three, so the two halves still agree with each other.

## What is missing, per target

- **aarch64.** pxx's own model carries floats as GP bits in ONE 8-slot save
  area (`__pxx_va_arg_cross`), so there is no two-class problem — but AAPCS64 is
  what gcc implements, and an aggregate >16 bytes is passed by reference there
  while pxx's fixed-param path already has a view on that. Start from
  `ABIA64CdeclArgSlot` and make the variadic tail ask it.
- **arm32 / riscv32.** `__pxx_va_arg_cross32` already steps by whole 4-byte
  words since the parent's fix (`(size + 3) & ~3`), so the receiving half needs
  only the size and one deref; the caller's tail arm in
  `ir_codegen_arm32.inc` / the riscv32 equivalent needs the same
  `IRArgRecId` read the i386 loop got. Watch the STRADDLE arm in
  `__pxx_va_arg_cross32`: it assembles an 8-byte scalar spanning the
  register/stack boundary, and an aggregate that straddles is a different
  question.

## The blocker is an ORACLE, not effort

`test-c-abi-mixed-link` is the only gate here with an outside opinion, and it
runs `x86_64` and `i386` — the two targets where gcc can produce a hosted
binary on this box. On the other three there is no gcc-compiled counterpart to
link against, so **a pxx-vs-pxx test agrees with itself whatever the convention**
— which is the sentence the parent family keeps having to relearn.

`test-c-abi-cross` does run all four cross targets and passes; it does not cover
this, which is the same "the population where two implementations can disagree"
argument. So the first piece of work is deciding what plays the oracle:
a cross gcc/binutils toolchain, a qemu-hosted link, or a hand-checked
`gcc -S` disassembly comparison of the argument setup (which is what the
fixed-param fix used before the mixed link existed).

Doing the emit without one is how the parent's sibling shipped a convention
that was wrong in both halves for months.
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

# 2026-09-03 (frankB) — the "no oracle on these three" premise is wrong for two of them, and half wrong for the third

This ticket says *"there is no MIXED-LINK oracle on these three ... which is why
they were not converted blind alongside the other two"*. The mixed-LINK part
stands: there is no cross gcc and no `lld` on this box, so nothing can be linked
for these targets. **But a mixed link was never the only oracle available.**

`clang --target={aarch64-linux-gnu,arm-linux-gnueabihf,riscv32-linux-gnu} -S`
compiles for all three with nothing installed, and reading the CALL SITE needs no
link and no run. `llvm-objdump-21` reads pxx's own output for these targets for
the other column. Method and the measured aggregate-placement table:
`devdocs/dev/differential-probes.md`, "A CROSS-TARGET ABI ORACLE EXISTS ON THIS
BOX, AND IT IS NOT A CROSS GCC". The aarch64 rows are worked through on the
sibling ticket
`bug-a-an-aggregate-argument-is-a-pointer-by-construction-on-aarch64`.

Three things from that table bear directly on this ticket's three targets, and
none of them is guessable:

- **arm32 never goes indirect.** A 12-byte aggregate is passed in `r0,r1,r2` with
  the tail in `r3`. So the pointer this ticket describes is wrong on arm32 for
  every size, not only past a limit.
- **riscv32 does, at 2x XLEN.** A 12-byte aggregate is a pointer in `a0` with the
  tail in `a1` — which is what pxx already emits, so on riscv32 the current
  behaviour is CORRECT for that shape and wrong for smaller ones. A probe that
  used a big struct would certify the bug.
- **riscv32 takes `{double,double}` in `fa0,fa1` and `{float,float,float}`
  indirectly.** The FP-struct rule stops at two members, so "an HFA goes in FP
  registers" is not portable between aarch64 and riscv32.

`long` is 4 bytes on the two 32-bit targets, so a struct chosen for its 64-bit
size is a different shape there; size the probe in explicit widths.

Still true and unchanged: this is a PLACEMENT oracle. It cannot see a value read
back from the wrong place, and the running-program oracle (a dynamic call into
the target's own glibc, aarch64 and arm32 only) cannot reach a by-value aggregate
because no libc entry point takes one. riscv32 is covered by the placement oracle
alone.

# 2026-09-04 (frankB) — THE PLACEMENT TABLE FOR ALL THREE, MEASURED. The three rules are three rules, and two of them differ from that target's own FIXED-parameter rule

This ticket has said "the first piece of work is deciding what plays the oracle"
since it was filed. The oracle is settled (clang's call site, no link, no run)
and here is the table it produces, so nobody has to re-derive it. One variadic
callee, `extern void v(int n, ...)`, four aggregate shapes, each call carrying a
LEADING scalar (so the bank is already partly spent) and a TRAILING integer (so
the bank state after the aggregate is observable). Sizes in explicit widths
because `long` is 4 bytes on the two 32-bit targets.

| shape | size | aarch64 | arm32 | riscv32 |
| --- | --- | --- | --- | --- |
| `{int,int}` | 8 | `x1` packed, tail `w2` | `r1,r2`, tail `r3` | `a1,a2`, tail `a3` |
| `{int,int,int}` | 12 | `x1,x2`, tail `w3` | `r1,r2,r3`, tail on the STACK | POINTER `a1`, tail `a2` |
| `{double,double}` | 16 | `d0,d1`, tail `w1` | `r2,r3` + STACK, split | POINTER `a1`, tail `a2` |
| `{int x6}` | 24 | POINTER `x1`, tail `w2` | `r1,r2,r3` + STACK, split | POINTER `a1`, tail `a2` |

## The three things that are not guessable, and each one breaks a port

**1. aarch64's variadic rule is its FIXED rule, unchanged — including HFAs.**
`{double,double}` still goes in `d0,d1` in the variadic tail on AArch64 Linux.
That is worth stating because the opposite is a common belief (Apple's variant
does drop HFA treatment past the named parameters, and Apple's is the platform
people have read about). So the aarch64 half of this ticket is exactly what its
own text says: make the tail ask the same oracle the fixed parameters now ask
(`ABIA64ArgDesc` / `ABIA64ArgPlace`, landed 2026-09-04 in
[[bug-a-an-aggregate-argument-is-a-pointer-by-construction-on-aarch64]]), with
the argument's `IRArgRecId` standing in for the parameter that does not exist.

**2. arm32 SPLITS an aggregate between the registers and the stack.** `{int x6}`
puts 6,7,8 in `r1,r2,r3` and 9,10,11 on the stack, in one argument. AAPCS64 is
all-or-nothing and says so at length in `ABIA64ArgPlace`; AAPCS32 is not, and a
marshaller ported from the aarch64 one will place the head and strand the tail —
which is a plausible wrong answer rather than a crash. `{double,double}` is the
same shape plus 8-byte alignment: `r2,r3` then stack, with `r1` skipped.

**3. riscv32's variadic rule is NOT its fixed rule.** The fixed-parameter table
on this ticket records `{double,double}` in `fa0,fa1`; in the variadic tail
clang passes it INDIRECTLY. Everything over 2x XLEN is a pointer there, FP
members included. So the one target where an earlier note said "the current
pointer is CORRECT for a 12-byte struct" is correct for a wider set than that
note implies — and wrong only at 8 bytes and below.

**Nothing here is a proof that a value READS BACK right.** It is a placement
oracle: it reads the call site and never runs. The receiving half
(`__pxx_va_arg_cross`, `__pxx_va_arg_cross32`, and the straddle arm this
ticket's body already warns about) has to agree with whatever the caller does,
and a pxx-vs-pxx test cannot see them disagreeing in the same direction — the
sentence this family keeps relearning, and one measured instance of it is on the
sibling ticket, where the by-value test PASSES on the pre-fix compiler byte for
byte.

Probe kept at the shape above rather than checked in: it needs an `extern`
callee that is never defined, so it compiles under clang and does not link, and
the pxx column comes from `llvm-objdump-21` plus pxx's `.map`. The method is in
`devdocs/dev/differential-probes.md`.
