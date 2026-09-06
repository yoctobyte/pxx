# C frontend: silent-wrong vs refusal, for beta 0.1

Asked for by the owner via frankuser, 2026-09-06: a beta may ship a backlog of
known REFUSALS, because a user meets a diagnostic and can act on it. What it
must not ship is an **unenumerated** set of things that compile, run, and are
wrong — those cannot be discovered from a message.

**This list is DERIVED, not maintained.** Every ticket in it carries the literal
heading `## RELEASE-RISK: SILENT-WRONG`, so the current set is:

```sh
grep -rl 'RELEASE-RISK: SILENT-WRONG' devdocs/progress/
```

Cite that grep, never this file's table — a list transcribed into prose is stale
the first time somebody files or closes one, and this document has no way to
know. If the two disagree, the grep is right.

## The set as of 2026-09-06, all re-measured here rather than read

| ticket | prio | what is silently wrong |
| --- | --- | --- |
| `bug-c-__thread-is-accepted-and-silently-ignored-...` | 60 | `__thread int tv = 7;` compiles, runs, prints 7, and the object has **zero** `.tbss`/`.tdata` sections against gcc's one. Every thread shares one copy. |
| `bug-c-long-double-is-8-bytes-in-pxx-and-16-in-gcc` | 35 | `sizeof(long double)` and `sizeof(struct { long double x; })` are 16 under gcc, 8 under pxx, same source, both silent. An aggregate carrying one disagrees about its own size across any real C boundary. |
| `feature-c-crtl-stdio-buffering-and-setvbuf` | 55 | `setvbuf` discards all four arguments and returns 0 — which C99 7.19.5.6 defines as SUCCESS. A caller that correctly checks the return is told its request was honoured when nothing happened. |
| `bug-c-crtl-utoa-digit-loop-is-unbounded` | 25 | **Conditional.** Needs a wrong `base` reaching `__crtl_utoa`, which no user program supplies directly; when it fires it corrupts the stack with no diagnostic. Listed because the ticket is parked as the amplifier for an unnamed defect, so its trigger is precisely what nobody has found. |

## Everything else open in the lane is a REFUSAL, tooling, or a decision

Refusals — loud, rc=1, a user can see them: hosted C on wasm32 (environ, then
va_arg), the pty family, `resolv.h`/the ns parser, sqlite under `--threadsafe`.
Not defects a release must hide; they are the backlog a beta is allowed to have.

Neither: `feature-c-diagnostics-name-the-module-they-are-in` (diagnostic
quality — it makes refusals BETTER, which is the opposite failure mode),
`perf-c-parse-codegen-large-file-superlinear`, `feature-c-csmith-differential-fuzzing`,
`idea-c-realworld-test-targets`, `feature-c-esp-conformance-coverage`,
`feature-c-package-namespace-decision`.

## Two LATENT ones, deliberately not in the set

Neither is wrong today, and both become silent-wrong on a specific future edit.
They are worth naming in the same breath because "not currently reachable" is
how the set stays artificially short.

- `bug-c-the-32-bit-va-arg-set-is-complete-only-because-two-targets-cannot-compile-c-yet`
  — wasm32 is absent from the four sets, and today that is inert because the
  variadic PROLOGUE has no wasm32 arm and refuses first. Add that arm without
  the sets and wasm32 silently takes the 8-byte two-bank layout, wrong from the
  second variadic argument on.
- `bug-c-the-sizeof-descriptor-walk-answers-from-tyunknown` (`low-prio/`) — the
  census found exactly one reaching site in 10932 walks over 629 files plus lua
  and sqlite, and there the unrecorded default of 8 is the RIGHT answer for a
  function pointer. Correctly parked; it is one operand shape away from being
  wrong, which is the whole content of that ticket.

## The contrast worth putting in the release notes

**Pascal REFUSES `threadvar` outright. C ACCEPTS `__thread` and ignores it.**
One missing mechanism, opposite failure modes, and C is where `errno` lives
(`bug-a-errno-is-one-global-across-all-threads-...` is one instance of exactly
this absence). A reader can act on that difference: on the Pascal side they are
told, on the C side they are not.
