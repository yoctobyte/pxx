---
slug: decide-c-crtl-rand-max-is-conforming-but-breaks-real-code
title: "crtl's RAND_MAX is 32767 — conforming, but real C assumes 2^31-1"
track: U
prio: 40
type: decide
blocked-by: []
status: backlog_new
owner: unassigned
created: 2026-08-26
summary: "crtl defines RAND_MAX as 32767 and rand() returns [0,32767]. C99 7.20.2.1 only requires RAND_MAX >= 32767, so this is conforming — but every mainstream libc uses 2147483647 and real programs branch on the value. busybox editors/awk.c has an #error for anything else and is the only busybox file still blocked on a non-library gap. Raising it is a behaviour change to a shipped library, not a defect fix, so it is a call to make, not a bug to close."
---

# RAND_MAX: conforming vs. what code actually expects

Surfaced by the busybox 1.37.0 sweep. `editors/awk.c` is now the ONLY busybox
file blocked by something other than a missing crtl function:

```
pascal26:3416: error: #error in editors/awk.c:
  Not implemented for this value of RAND_MAX
```

awk's source handles exactly two cases, `RAND_MAX == 0x7fffffff` and
`RAND_MAX == 0x7fffffffffffffff`, and `#error`s on anything else.

## The state of things

`lib/crtl/include/stdlib.h`:

```c
#define RAND_MAX 32767
```

`lib/crtl/src/stdlib.c` implements C99 7.20.2.2's own example generator and
returns `(state / 65536) % 32768`, i.e. `[0, 32767]`. The header comment there
is explicit that the SEQUENCE is not portable and that matching glibc's was
rejected deliberately — that reasoning is about the sequence, and says nothing
about the RANGE.

## Why this is a question and not a bug

C99 7.20.2.1 requires only `RAND_MAX >= 32767`. pxx is conforming. Under the
FPC-parity ceiling's logic — we care about compiling correct code, not about
mimicking a reference implementation — a program that assumes more than the
standard promises is the program's problem.

Against that: glibc, musl, the BSDs and every Linux libc use 2147483647.
"Real C code compiles" is the actual goal of the C frontend, and 32767 is a
value no modern program is written against. It also costs precision: a program
building a double from `rand()/RAND_MAX` gets 15 bits instead of 31.

## The options

1. **Leave it.** Conforming; busybox awk is one file; pxx does not chase
   implementations.
2. **Raise RAND_MAX to 2147483647** and widen `rand()` to return 31 bits (still
   the standard's own generator, just not discarding the high half). Unblocks
   awk and matches every libc a C program was written against. Changes the
   values `rand()` returns, so `test/crand_props.c` needs re-reading — it
   asserts properties, not values, so it should survive, but that must be
   checked rather than assumed.
3. Raise the macro only, leaving `rand()` at 15 bits. **Rejected outright** —
   that is the one combination that is a genuine defect: code scaling by
   `RAND_MAX` would silently lose 16 bits of range.

Option 2 is the recommendation, but it is a behaviour change to a shipped
library and the user's call.
