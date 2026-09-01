---
slug: feature-a-xtensa-should-not-need-a-flag-to-build-a-large-image
track: A+S
prio: 50
type: feature
status: new
found: 2026-08-31
found-by: frankA
owner: ""
blocked-by: []
summary: "An unrelated RTL commit (4419e1aa7) pushed the test-xtensa xt_backjump call0 arm past CALL8 reach WITHOUT changing the image size (622444B both ways) -- it reordered __pxx_run_finalizers to the tail, 36618 bytes out of reach of its earliest caller -- so the margin is not a property of the program and any RTL edit can flip any near-512KiB image; that arm now passes --xtensa-long-calls explicitly. --xtensa-long-calls builds a large image today (bug-a-xtensa-cannot-widen-a-forward-call-..., closed) but the user has to know it exists, and a program that needs it fails with an error until they do. The right default is to widen only the forward calls that need it. The per-body relaxation that closed the forward JUMP wall does NOT transfer -- a jump's fixups are per-body and a call's are whole-program, so the analogous retry is a second parse. A veneer pool is the untried candidate and is more attractive here than it was for jumps: CALL0 reaches +-512 KiB against J's +-128 KiB, so a trampoline at the END OF THE CALLING BODY is within the call site's reach, where the jump case's veneer was not."
---

# xtensa should not need a flag to build a large image

- **Filed:** 2026-08-31 by frankA, on closing
  [[bug-a-xtensa-cannot-widen-a-forward-call-so-a-big-image-still-refuses-to-build]]
  with the flag rather than with the fix.
- **Nothing is broken.** The flag works and the error names it. This is about
  the default.

## Why it was prio 35, and why it is 50 now

The original reasoning: *"Every xtensa program that is not the compiler itself
fits inside CALL0's range, so the population that needs this is one program, and
that program has an answer."*

**Both halves of that are now measured false** (frankB, 2026-09-01).

- **The population is not one program.** The `xt_backjump` row of `test-xtensa`
  is a 118 KB generated test program, not the compiler, and its call0 arm no
  longer fits. It was passing on 2026-08-31.
- **"That program has an answer" understates the failure mode.** The margin is
  not a property of the program. `4419e1aa7` (an OOM-reporting fix in
  `compiler/builtin/builtinheap.pas`) pushed this arm over the wall **without
  changing the image size at all** -- 622444B of code before and after. It
  REORDERED the image: `__pxx_run_finalizers` moved to the tail, 620060, while
  its earliest caller stayed at 59154. 560906 apart, **36618 bytes past** CALL8's
  524288.

So any RTL edit can silently push any near-512 KiB xtensa image out of reach,
and it does not need to add a byte to do it. The failure is a hard build refusal
naming a flag, not a miscompile -- which is why this is 50 and not higher.

## The two candidates, and what each owes

**A veneer pool.** At `ApplyCallFixups`, an out-of-range forward call is
redirected to a trampoline that does the long-form jump. The trampoline has to
be within CALL0's ±512 KiB of the CALL SITE, which rules out the image tail and
points at *the end of the calling body* — reachable, since no single body is
512 KiB. What it owes: somewhere to put it. The body is already emitted and
everything after it has been placed, so this still needs either reserved space
per body (a cost paid by everyone, which is what the flag already is) or a
layout pass that can insert.

**Two-pass compilation.** Compile, collect the set of call sites that did not
reach, compile again with exactly those widened. Correct and minimal in output
size; costs a second parse, and needs the driver to be re-entrant, which is the
part nobody has checked.

## Do not reach for the jump fix

`IREmitMachineCodeXtensa` relaxes by re-emitting ONE BODY, which is bounded and
whose restorable state is enumerated in a comment there. Calls are patched
whole-program. The shape looks identical and is not — see the closed ticket.

## How that was measured

Direct swap of the one buildable file in the watcher's range, no bisect and no
compiler rebuild -- `builtinheap.pas` is a *builtin*, consumed when compiling
the target program, so the arms differ by that file alone:

```
git checkout 156be41b504a -- compiler/builtin/builtinheap.pas   # last good
  ./pascal26 --target=xtensa --platform=posix --xtensa-soft-mulhigh xt_backjump.pas
  -> ok:  [code=622444B  procs=171]
git checkout HEAD -- compiler/builtin/builtinheap.pas
  -> error: forward call to __pxx_run_finalizers at 59154 cannot reach 620060
```

Both arms ran and answered differently, so the comparison is not vacuous. The
`--xtensa-long-calls` build of the same source succeeds at code=622444B, and the
windowed arm builds with NO flag at 556908B -- the two ABIs lay the image out
differently and only call0 is over.

## Size is NOT the condition — distance is

Sharpened by frankS, 2026-09-01, from the numbers above, and it inverts the
obvious reading:

| ABI | code size | verdict |
| --- | --- | --- |
| call0 | 622444 B | **FAILS** |
| windowed | 556908 B | **builds** |

Both are over CALL8's 524288. **The larger image is the one that builds.** So
image size is not what decides this; **max caller->callee distance** is, and
size is only a proxy for it. That is precisely why a commit which changed no
bytes could flip it: `4419e1aa7` moved the callee, not the byte count.

Two consequences worth carrying:

- **A passing build on one ABI is not headroom.** It says THAT LAYOUT keeps
  every call in range. Read as "we are comfortably under", it is wrong.
- **An image-size watch would not catch this** — it would have stayed green
  straight through this regression. The number worth watching is closest
  approach to +-512 KiB across all call sites, which the backend already
  computes in order to emit the refusal at all. That is cheaper than either
  candidate below and changes no codegen; filed separately as
  [[idea-t-watch-the-closest-call-approach-not-the-image-size]].

Also from frankS, against my own argument: **do not justify this prio with an
"ESP images are trending large" story.** Empty bare-profile xtensa is 43428 B
and `uses softfloat` adds ~54 KB (see
[[bug-a-the-esp32-bare-image-doubled-in-code-and-grew-half-again-in-bss]]), so
bare ESP has 5-12x headroom and several doublings to go. The population that
actually hits this is **hosted** xtensa, which is growing deliberately as
frontends lean on it as a differential oracle — every new program compiled for
it is another chance to land a RED whose diff looks nothing like a size change.
That, not ESP, is the cost curve that justifies 50. Revisit upward if hosted
xtensa sweeps start hitting it repeatedly.

## What this does NOT change

The two candidates below are unaffected; nothing here argues for one over the
other. It raises how often the default bites, not how it should be fixed.

