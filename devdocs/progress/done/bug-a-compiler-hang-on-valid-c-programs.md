---
summary: "pxx compiler HANGS (non-termination, 100% CPU) compiling two valid C programs gcc builds in <1s — pr23324.c (bitfields+empty union) and pr44164.c (nested struct + empty compound literal); worst class: no output, no error"
type: bug
track: A
prio: 60
---

# pxx compiler hangs (non-termination) on two valid C programs

- **Type:** bug (compiler non-termination). **Worst class** — not a wrong answer, no
  output at all: the compiler never returns. A hang in a gate wedges the whole run.
- **Track:** A (front/middle-end — lowering or an optimization pass that doesn't
  converge). Both inputs are valid C that gcc compiles in well under a second.
- **Found by:** the one-time gcc c-torture harvest (2026-07-15),
  [[feature-t-gcc-torture-runner]]. Surfaced because pxx spun 35 min at 100% CPU on
  the first one and stalled the harvest until a compile timeout was added.

## Repro

```
timeout 5 compiler/pascal26 -Ilib/crtl/include -Ilib/crtl/src \
  library_candidates/gcc-torture/execute/pr44164.c /tmp/x   # exit 124 = HANG (24 lines)
timeout 5 compiler/pascal26 -Ilib/crtl/include -Ilib/crtl/src \
  library_candidates/gcc-torture/execute/pr23324.c /tmp/x   # exit 124 = HANG (133 lines)
```

Both: pxx `exit=124` (killed by timeout, running at 100% CPU); `gcc -w -c <f>` compiles
each in <1s. No diagnostic, no partial output — pure non-termination.

## Leads (reduction started, NOT isolated — that's the fix)

- **pr44164.c** (24 lines, the tractable one): nested structs `X{Y{YY{Z{int}}}}` + an
  **empty compound literal** `a.b = (struct Y){}` assigned to a nested field, inside a
  `__attribute__((noinline,noclone))` function that reads `p->i`, clobbers `*p` via the
  aggregate store, then reads `p->i` again (the gcc PR44164 store-forwarding/aliasing
  shape). Minimal reductions of JUST the empty compound literal on a nested struct do
  NOT hang (tested `struct Y {}`, `(struct Y){}` one/two levels deep — all terminate),
  so the trigger needs the aliasing/self-referential-store context or an opt pass that
  fails to converge on it. Start there.
- **pr23324.c** (133 lines): many odd-width signed bitfields (`:2 :3 :5 :6 :7 :9 :10
  :12`) across nested structs + an **empty union** `union at6 {}` + `long long`. May be
  a distinct root cause (bitfield layout) or the same non-convergence; also referenced
  in [[bug-c-bitfield-promotion-and-layout-cluster]] but centralized here as a hang.

## Why it matters beyond these two files

A compiler that can non-terminate on valid input is a latent hazard for every corpus
and the self-host gate. The watcher now guards against a stall (compile timeout in the
harvest; testmgr's per-job timeout catches it in tiers), but the underlying
non-termination should be fixed, not just timed out around.

## Acceptance

Both files compile in bounded time under pxx (match gcc's sub-second); a minimal
reduced repro is added as a `test/` regression; if the two have distinct root causes,
split into two fixes but keep this ticket until both terminate.

## Log
- 2026-07-15 — resolved, commit PENDING.
