---
slug: bug-a-no-c-translation-unit-builds-for-xtensa-and-two-different-things-stop-it
title: "No C translation unit builds for xtensa, and two different things stop it"
track: A
prio: 40
type: bug
status: done
created: 2026-09-04
found-by: franks-ab
owner: ""
blocked-by: []
summary: "FIXED AND ACCEPTED 2026-09-04 at binary 1060640e02fb16f5. Both halves closed, by two different commits. The BACKEND half (`call0 target 56674 is not 4-aligned' on crtl's ctype.c) was a missing entry alignment, not a missing feature: 0bc9d654b routes all 22 `Procs[X].BodyAddr := CodeLen' sites through SetProcBodyAddrHere, which pads to 4 on xtensa only. The FRONTEND half (`C program entry stub not implemented for this target yet') is 233e693bb, which also widened the four 32-bit va_arg-set tests to include xtensa IN THE SAME COMMIT, as bug-c-the-32-bit-va-arg-set-... requires. A third defect the stub UNCOVERED -- 64-bit variadic arguments silently dropping their high word -- is 7574a5f8d. The acceptance now passes: test/c_crtl_syscall_guarded_bodies.c builds and runs under qemu-xtensa and its ten rows are byte-identical to the i386 run, so the generated 329-number xtensa syscall arm (f25e4c723) is measured and no longer method-only. It needs --platform=posix (the xtensa default is the ESP profile, which deliberately has no argc and no exit_group) and --xtensa-long-calls, which is feature-a-xtensa-should-not-need-a-flag-to-build-a-large-image and is a separate open ticket -- whose p35 rationale this run REFUTES, see the log below."
---

# Two independent blockers, and only the first one is the one people know about

Both reproduce in one line each, at `aaf09343d1cb`.

```
$ ./compiler/pascal26 --target=xtensa test/c_crtl_syscall_guarded_bodies.c out
pascal26:5: error: C program entry stub not implemented for this target yet

$ ./compiler/pascal26 --target=xtensa --platform=posix <same>      # identical

$ ./compiler/pascal26 --emit-obj --target=xtensa <same> out.o
pascal26:158: error: target xtensa: call0 target 56674 is not 4-aligned;
  CALL0/CALL8 encode a WORD offset and a stray byte is silently truncated
  away by the div below
  in: lib/crtl/src/ctype.c   near: isalpha
```

`--emit-obj` needs no entry stub, which is why it reaches the backend at all —
and that is what makes these two separate bugs rather than one. **Landing the
stub does not get a C object built; it gets you to the second error.**

## The second one is a guard doing its job, not a missing feature

The message is explicit that CALL0/CALL8 encode a **word** offset and that the
`div` below would truncate a stray byte **silently**. So somebody met this,
worked out that a misaligned target produces a wrong branch rather than a
diagnostic, and put the refusal in. That is the right shape. What is missing is
the alignment itself: whatever lays out `.text` for xtensa is not padding
function entries to 4.

`ctype.c` is the first crtl module compiled, so it is where this always
appears; it is not about `isalpha`.

## Why it is filed now

`lib/crtl/include/sys/syscall.h` gained a generated xtensa arm on 2026-09-04
(`f25e4c723`, 329 numbers from `devdocs/dev/syscall-maps/xtensa.txt`). Its
block says in full that nothing can exercise it. The arm32 arm was confirmed by
running `test/c_crtl_syscall_guarded_bodies.c` under `qemu-arm` and matching
i386 row for row; **that check is exactly what these two bugs prevent**, and it
is the acceptance for this ticket:

    ./compiler/pascal26 --target=xtensa test/c_crtl_syscall_guarded_bodies.c out
    tools/run_target.sh xtensa out        # must equal the i386 run

`qemu-xtensa` is installed and `tools/run_target.sh` already has an xtensa arm,
so nothing else is needed to close it.

## What NOT to conclude

**This is not a reason to distrust the xtensa syscall numbers.** They come from
the same sweep and the same controls as arm32's, and arm32's were independently
corroborated byte-for-byte by a rewritten extractor. What is missing is
evidence of the *second* kind — a running program — and that is a different
claim from a wrong table.

Related: [[bug-c-the-32-bit-va-arg-set-is-complete-only-because-two-targets-cannot-compile-c-yet]]
says its `va_arg` slot set is correct **only** because xtensa and wasm32 cannot
compile C, and asks for the set to be fixed in the same commit as the stub.
That is a hard requirement on the first half of this ticket.
[[bug-c-no-c-program-entry-stub-for-wasm32-so-no-c-program-can-target-it]] is
the same first half for the other target.

## Log
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.

## Closed — what it took, and the part that was not in the ticket

The ticket said "two different things stop it" and was right about both, but the
count was two because that is how far the instrument could see. **The stub
uncovered a third.**

### The acceptance, run

```
$ ./compiler/pascal26 --target=xtensa --platform=posix --xtensa-long-calls \
      test/c_crtl_syscall_guarded_bodies.c out       # rc 0
$ tools/run_target.sh xtensa out > xt.out            # rc 0, ten rows
$ diff xt.out i386.out                               # IDENTICAL
sched_getscheduler   errno=0     mlock       errno=0     statfs   errno=0
sched_getparam       errno=0     munlock     errno=0     flock    errno=9
sched_yield          errno=0     acct        errno=1     prctl    errno=22
                                                         readv    errno=9
```

`--xtensa-soft-mulhigh` is NOT needed.

### The third defect, which only the acceptance could find

With the stub landed and the alignment fixed, the census still ran — and would
have been believed, because its ten rows are `%s errno=%d` and both survived.
The probes that did not survive were the ones nobody had a reason to run until a
C program could exist at all:

    printf("%llx", 0x1122334455667788)   ->  55667788      (high word dropped)
    printf("%.3f %.3f", 1.5, 2.25)       ->  0.000 0.000
    printf("%d %.3f %d", 7, 1.5, 8)      ->  7 0.000 1     (the 8 read as 1)

Both 64-bit arms of the xtensa direct-call ladder were guarded by
`i < Procs[procIdx].ParamCount`, false for every variadic-tail argument. Fixed
in `7574a5f8d` by asking `Arg32Class`, plus `ABIXtensaVaArgSlotAlign` for the
parity half. **A census whose every row is a small int and a string cannot see
this**, which is worth saying out loud next to a table that was just declared
measured: the ten rows are real evidence about the syscall NUMBERS and no
evidence at all about the printf that prints them. They are separate claims.

### What the run says about the OTHER ticket's ranking

[[feature-a-xtensa-should-not-need-a-flag-to-build-a-large-image]] holds p35 on
the stated grounds that *"the only program known to approach the wall is that
row, which is awk-generated specifically to be large, so it DEFINES a population
rather than sampling one — the hazard is real but conditional on some real image
getting near 512 KiB, and none is."* **That premise is now false.**
`c_crtl_syscall_guarded_bodies.c` is a hand-written C program of ordinary size
whose image is ~665 KB once crtl is in it, and without the flag it refuses:

```
pascal26:58: error: target xtensa: the forward call to __pxx_run_finalizers at
  code offset 58526 cannot reach its body at 664880 (CALL0/CALL8 reach +-512 KiB)
```

The wall is not a property of deliberately-large generated programs; it is a
property of **linking crtl at all**, so every C program on this target meets it.
Re-ranking is that ticket's owner's call and I have not touched its `prio:`;
what I have done is correct its summary so the next reader is not deciding from
the refuted sentence.
