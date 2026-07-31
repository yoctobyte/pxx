---
summary: "C: main() falling off the end returns stack garbage instead of 0 (i386)"
type: bug
track: C
prio: 65
---

# `main()` without a `return` yields a garbage exit status

- **Type:** bug (C frontend) — **Track C**
- **Found:** 2026-07-31 by Track T, triaging the c-conformance leg of
  [[regression-cascade-b45c759f9e65]].
- **Standard:** C99 §5.1.2.2.3 — reaching the `}` of `main` is equivalent to
  `return 0;`. gcc oracle agrees (exit 0).

Filed as a `bug-` rather than a `compat-c-*` ticket under the escape rule: this
is **silent wrong behavior** (a wrong exit status a caller acts on), not a
diagnostic-parity nicety.

## Repro (measured, not inferred)

`library_candidates/c-testsuite/tests/single-exec/00211.c` — 12 lines, `main`
ends without a `return`:

```c
extern int printf(const char *format, ...);
#define n 0xe
int main()
{
    printf("n+1 = %d\n", n+1);
}
```

Minimal pair, both built with `pascal26 --target=i386`, same binary run three
times each:

| source | run 1 | run 2 | run 3 |
|---|---|---|---|
| `main(){ printf("x\n"); return 0; }` | 0 | 0 | 0 |
| `main(){ printf("x\n"); }`           | **220** | **172** | **188** |

gcc on the same file: exit 0. `pascal26` x86-64 and arm32: exit 0 — **by luck**,
the return register happens to hold 0 there, which is why this hid for so long.

## Layer

The frontend, not the backend. Adding an explicit `return 0` makes i386 exit 0
deterministically, so the i386 return-value path is sound; nothing supplies the
implicit zero when the function body simply ends. Fix belongs wherever C
function bodies are lowered — apply it for `main` specifically (C99 exempts only
`main`; any other non-void function falling off the end stays undefined and
should keep whatever diagnostic it has today).

## Why it matters beyond one test

This is the `test-c-conformance-i386#shard0/6` red that has been carried in
tstate all day, and it is **nondeterministic**: `00211.c` has reported
`exit=188`, `exit=140`, `exit=76` across three consecutive full runs
(reports `20260731T131923Z-b45c759`, `20260731T155147Z-78847f9`,
`20260731T162036Z-6104264`), plus 220/172/188 locally. A red whose failure
signature changes every run is the kind that gets dismissed as flake — it isn't;
it's a real bug that reads garbage.

## Triage note for the cascade ticket

[[regression-cascade-b45c759f9e65]] says "treat as ONE root cause until triage
proves otherwise; do NOT fan out per-job tickets." Triage has now proved
otherwise for this leg: the c-conformance shards are a genuine, reproducible
frontend bug and are **separable** from the rest of that cascade
(`test-sqlite-threads-*`, `test-lua-cross`), which remain unexplained. Splitting
this one out is deliberate, not a violation of that instruction.

---

## The conformance shards went GREEN — that is a MASKING, not a fix (2026-07-31)

`test-c-conformance-*` reported FIXED at `4790e38cdd9f`. **This bug is not
fixed.** The green came from `3f90af303`, an honest revert of `lib/crtl`
(div/ldiv/lldiv/llabs and the sscanf field-width fix) that removed the
*perturbation*, not the defect. The revert commit says so itself: the
functionality is "lost for now and wanted back once the i386 bug is fixed".

So the current green costs real crtl functionality — including the sscanf fix,
which mattered (`%15s` silently abandoned the scan). Do not close this ticket on
the strength of a green matrix, and do not let an auto-pin rule treat that green
as proof (see [[decide-track-t-autopin-criteria]]).

## Same defect as [[bug-c-i386-crtl-growth-corrupts-main-exit-code]]

That ticket (Track C, claimed) describes the same failure from the other end:
*"adding ANY code to lib/crtl corrupts an unrelated program's exit code"*,
bisected across four Track B commits, with output staying correct and only the
exit code going wrong. It calls the shape "alarming" and concludes crtl
*growing at all* disturbs something on i386.

**These are one bug, and this ticket explains the other's mystery.** If the C
frontend emits no implicit `return 0`, `main`'s exit value is simply never set —
so it is whatever the last executed code happened to leave in the return
register. Then:

- growing `lib/crtl` changes which code ran last ⇒ the exit code changes,
  without crtl corrupting anything at all;
- programs that never call the new functions are still affected — no puzzle,
  since the value was never theirs to begin with;
- the *output* stays correct, because only the return value is unspecified;
- x86-64 and arm32 "pass" by luck, the register happening to hold 0.

Measured evidence for the mechanism (i386, same binary three runs each):
explicit `return 0` ⇒ 0, 0, 0; implicit ⇒ 220, 172, 188. gcc oracle: 0.

**Consequence for sequencing:** fixing this unblocks restoring the reverted
crtl work. Chasing "what in crtl corrupts the exit code" would be chasing a
symptom — nothing corrupts it; nothing ever set it.
