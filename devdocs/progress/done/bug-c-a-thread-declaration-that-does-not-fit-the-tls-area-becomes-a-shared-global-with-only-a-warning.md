---
slug: bug-c-a-thread-declaration-that-does-not-fit-the-tls-area-becomes-a-shared-global-with-only-a-warning
title: "a C `__thread` that does not fit the per-thread area silently becomes ONE copy shared by every thread — the identical Pascal declaration is refused"
type: bug
track: C
prio: 50
status: done
created: 2026-09-19
found-by: frankS
tags: [tls, threadvar, cfront, silent-wrong-value, diverging-policy]
blocked-by: []
summary: "RESOLVED 2026-09-19 (frankB). **The fork is answered: C now Errors on the ONE refusal the programmer can fix and keeps warning on the four that are OUR limits.** The filing measurement is exact; its scoping is not. TryAssignThreadVarStorage has FIVE refusal reasons and the ticket's \"not reachable today by accident\" was measured on the fifth only -- the other four fire with NO FLAG AT ALL, measured at HEAD: ARCH on every non-x86-64 target, NOINSTALL on every --emit-obj/--shared build, ARRAY on `__thread int b[4];`, TYPE on a `__thread` struct. So \"C should just Error like Pascal\" would delete `__thread` from everything but hosted x86-64 scalars, for programs that are CORRECT today (single-threaded, one shared copy IS one copy per thread). THE GOAL SENTENCE IT SETTLES: do we want a C program that asks for thread-local storage and cannot have it to STOP when the programmer's own build flag is the cause, and to keep building with a warning when the limit is ours? YES. TLSREFUSE_AREAFULL is now an Error -- the same answer Pascal gives for the identical mistake, and its message already names -dPXX_TLS_USER_4K/_8K/_16K, so the stop is actionable; the other four stay warnings. `reason` travels as a CODE so the one `if` still chooses and no second refusal site exists. A SECOND DEFECT THE TICKET DOES NOT NAME, measured not assumed: the warning fired once per COMPILATION, so a TU with a `__thread` array AND a `__thread` struct reported the array and suppressed the struct ENTIRELY -- each hidden declaration is its own latent data race. Now once per REASON, keeping the original anti-noise contract. THE TICKET'S THIRD OPTION (Error only when the TU creates a thread) WAS COSTED AND NOT BUILT: no such signal exists and the flag would be per-TU while C compiles per-TU, so an --emit-obj file linked into a threaded program would still degrade silently -- it narrows the hole, not closes it. TWO CORRECTIONS TO THIS TICKET, both misleading: C's arm is at cparser.inc:10302, NOT in pasparser_decl.inc as \"What must be true before this is closed\" states; and cparser.inc's \"population of __thread under test/, lib/ and examples/ is ZERO\" is now TWO (corrected in place). GUARD: three test-core rows -- rows 1 and 2 are the change and each was shown to fail INDEPENDENTLY on the pin (pin compiles area-full rc=0 with ZERO diagnostics; pin reports one warning where two are asserted), row 3 is the INVARIANT and passes on the pin deliberately. Unchanged and re-run: c_thread_local_is_per_thread and c_block_static_survives_a_storage_class."
---

# How it was found

While deciding whether the threadvar-area prescan
(`feature-a-the-threadvar-area-is-3072-bytes-of-bss-in-every-program-that-has-no-threadvar`)
could give C programs a zero-byte area the way it now does for Pascal and NilPy.
It cannot, and this is why: the NilPy arm is safe **because** a threadvar on its
ambient Pascal chain is refused loudly, with the flag to raise named in the
message. C has no such backstop.

# The measurement

```c
#include <stdio.h>
__thread int counter;
int bump(void) { counter += 7; return counter; }
int main(void) { counter = 0; printf("got=%d\n", bump()); return 0; }
```

| build | outcome |
| --- | --- |
| default area (3,072 B) | `ok:`, `got=7`, one copy per thread — correct |
| `-dPXX_TLS_USER_0` | **`warning:`**, `ok:`, `got=7` — one copy for the process |

and the same shape in Pascal at `-dPXX_TLS_USER_0` is
`error: threadvar counter: the per-thread variable area is full (0 bytes)`,
exit 1.

# The fork, stated as a goal and not as a mechanism

**Do we want a C program whose thread-locals do not fit to fail to build, or to
build and be wrong only when it uses threads?**

Arguments for keeping the warning: C's `#include`s mean a `__thread` can arrive
from a header the author never opened, so an Error can refuse a program over a
declaration that is never used by any thread; and single-threaded C is the
common case.

Arguments for the Error: it is the answer Pascal already gives for the identical
mistake, the message already names the flag that fixes it, and the failure it
prevents is a data race — the class this project pays the most for. A warning in
a build that prints `ok:` and hundreds of other lines is not a control.

A third option nobody has costed: Error only when the translation unit also
creates a thread, which is knowable at the same point the RTTI reader flag is.

# What must be true before this is closed

If the policy changes, the change is in `TryAssignThreadVarStorage`'s C arm in
`compiler/pasparser_decl.inc` and nowhere else — the allocator is one door and
the two policies are one `if`. Anything that adds a second refusal site is the
wrong fix.

# Worked 2026-09-19 (frankB) — the fork resolves on WHO CAN FIX IT, and four of the five reasons are reachable with no flag

**REPRODUCED FIRST, and then the framing did not survive.** The ticket's
measurement is exact and its scoping sentence is not: *"NOT URGENT AND NOT
REACHABLE TODAY BY ACCIDENT ... a C program needs ~768 ints of thread-local
storage, or an explicit -dPXX_TLS_USER_0/_1K, to get here."* That is true of
ONE of the allocator's five refusal reasons. Measured at HEAD, each with **no
flag at all**:

| reason | probe | reachable with no flag? |
| --- | --- | --- |
| ARCH (not x86-64) | `--target=riscv32/aarch64/i386` | **yes** — every cross target |
| NOINSTALL (no ELF entry) | `--emit-obj` / `--shared` | **yes** — every object build |
| ARRAY | `__thread int b[4];` | **yes** |
| TYPE (non-scalar) | `__thread struct S s;` | **yes** |
| AREAFULL | `-dPXX_TLS_USER_0` | no — needs the flag or ~768 ints |

So "C should Error like Pascal" is not a diagnostic policy change. It would
refuse `__thread` on every target but hosted x86-64 and in every object-emitting
build — **deleting a feature from programs that are CORRECT today**, because in
a single-threaded program one shared copy IS one copy per thread. That is the
regression argument already written at `TryAssignThreadVarStorage`, and it holds
for four reasons and not for the fifth.

## The fork, answered

> **Do we want a C program that asks for thread-local storage and cannot have it
> to STOP when the programmer's own build configuration is the cause, and to
> keep building with a warning when the limit is OURS?**

**Yes.** `TLSREFUSE_AREAFULL` is now an `Error` in C — the same answer Pascal
gives for the identical mistake, and the message already names the flag that
undoes it (`-dPXX_TLS_USER_4K/_8K/_16K`), so the stop is actionable. ARCH,
NOINSTALL, ARRAY and TYPE stay warnings: the programmer cannot fix those by
changing their build, and refusing would break working programs to protect
broken ones.

The ticket's third option — Error only when the TU also creates a thread — was
costed and **not built**. No such signal exists (`pthread_create` reaches the C
frontend as an ordinary external name), and the flag would be **per translation
unit** while C is compiled per TU: a `--emit-obj` file that declares `__thread`
and is linked into a threaded program would still degrade silently. It narrows
the hole rather than closing it, for a new mechanism.

## A second defect the ticket does not name, measured rather than assumed

The warning fired **once per COMPILATION** (`CTlsIgnoredWarned`). Measured
before the change, a TU declaring a `__thread` array AND a `__thread` struct —
two DIFFERENT reasons — reported the array and said nothing whatsoever about the
struct. Each silently degraded declaration is its own latent data race, so a
whole reason going unreported is the failure the warning exists to prevent,
wearing the shape of restraint. It is now once per REASON, which keeps the
original contract (N copies of one fact on a cross target would bury the other
diagnostics) and drops the part that hid a second fact.

## Two corrections to this ticket, both in the misleading direction

1. *"the change is in `TryAssignThreadVarStorage`'s C arm in
   `compiler/pasparser_decl.inc` and nowhere else"* — **the C arm is not in that
   file.** It is `CApplyThreadLocalStorage` at `compiler/cparser.inc:10302`.
   `pasparser_decl.inc` holds the allocator and Pascal's arm.
2. `cparser.inc` asserts *"The measured population of `__thread` under test/,
   lib/ and examples/ is ZERO (re-counted at this commit)"* — now **two**:
   `test/c_thread_local_is_per_thread.c` (the feature's own positive test) and
   `test/c_block_static_survives_a_storage_class.c`. Corrected in place.

The ticket's *"the allocator is one door and the two policies are one `if`"* is
kept and is why `reason` travels as a CODE: the one `if` remains, and what it
branches on is which reason. No second refusal site was added.

## Guard, and what each row is FOR

`test-core`, three rows. **Rows 1 and 2 are the change; row 3 is the
invariant** — it asserts NON-change and the pinned compiler agrees with it on
purpose, so it is not a control and must not be "fixed" to differ from the pin.

Positive control for rows 1 and 2 is the pin, and each was shown to fail
**independently** rather than assumed to, because the recipe halts at its first
failure:

- row 1 — the pin compiles the area-full program `rc=0` with **zero
  diagnostics** (it predates the warning entirely), against an asserted `rc=1`.
- row 2 — the pin reports **one** warning (`__thread buf:`) where the row
  asserts two and names both.
- row 3 — the pin warns and compiles for riscv32, which is exactly what the row
  asserts. Stated rather than glossed.

Two rc=1 results seen while probing were **not** this change and were attributed
before being reported: `--target=aarch64 --emit-obj` fails with *"no object
writer for --target=aarch64"*, and `--target=xtensa --emit-obj` fails with
*"PXXMemZero not found"* — the latter reproduces byte-for-byte with `__thread`
deleted from the same file.

Unchanged and re-run: `c_thread_local_is_per_thread` (`C THREAD-LOCAL OK`, all
six rows) and `c_block_static_survives_a_storage_class` (`6 rows OK`), both with
zero `__thread` warnings.

## Log
- 2026-09-19 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
