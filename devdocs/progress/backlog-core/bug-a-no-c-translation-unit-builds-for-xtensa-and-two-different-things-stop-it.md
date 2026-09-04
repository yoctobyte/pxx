---
slug: bug-a-no-c-translation-unit-builds-for-xtensa-and-two-different-things-stop-it
title: "No C translation unit builds for xtensa, and two different things stop it"
track: A
prio: 40
type: bug
status: backlog
created: 2026-09-04
found-by: franks-ab
owner: ""
blocked-by: []
summary: "MEASURED 2026-09-04 at binary aaf09343d1cb. A C PROGRAM refuses in the frontend -- cparser.inc:11666 `C program entry stub not implemented for this target yet', with or without --platform=posix. A C OBJECT gets further and dies in the BACKEND on crtl's own ctype.c: `target xtensa: call0 target 56674 is not 4-aligned; CALL0/CALL8 encode a WORD offset and a stray byte is silently truncated away by the div below'. So the whole crtl C surface is unreachable on xtensa and the two causes are independent -- fixing the stub alone gets you to the second one. The second is the interesting half: the refusal is a guard someone wrote against a silent truncation, so it is the good outcome of a real alignment bug, not a missing feature. Consequence today: sys/syscall.h's newly generated xtensa arm (329 numbers, f25e4c723) is correct by method and verified by nothing, because test/c_crtl_syscall_guarded_bodies.c -- the census that confirmed arm32 row for row against i386 -- cannot be built for this target."
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
