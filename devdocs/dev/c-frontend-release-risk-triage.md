# C frontend: silent-wrong vs refusal, for beta 0.1

Asked for by the owner via frankuser, 2026-09-06: a beta may ship a backlog of
known REFUSALS, because a user meets a diagnostic and can act on it. What it
must not ship is an **unenumerated** set of things that compile, run, and are
wrong — those cannot be discovered from a message.

**This list is DERIVED, not maintained.** Every ticket in it carries a literal
`## RELEASE-RISK: <state>` heading, so the current sets are:

```sh
grep -rl '^## RELEASE-RISK: SILENT-WRONG' devdocs/progress/   # cannot be discovered
grep -rl '^## RELEASE-RISK: DIAGNOSED'    devdocs/progress/   # still wrong, but it says so
grep -rl '^## RELEASE-RISK:'              devdocs/progress/   # the whole family
```

**ANCHOR THE PATTERN — `^## `, not a bare substring.** This is not tidiness; the
unanchored form was wrong within an hour of this file being written. It returned
FIVE files where the true set was three, because the literal also appears in
`LOGBOOK.md` prose, in a ticket's discussion OF the marker, and — worst — in a
`## (historical heading) RELEASE-RISK: SILENT-WRONG` line I added myself while
re-categorising `__thread`, which looked exactly like a heading to a substring
match.

The derived-list idea is right and the first spelling of it was not. **A list
computed by the wrong query is worse than a transcribed one**: it carries the
authority of being generated while answering a different question, and the
failure is silent — a longer answer reads as a more complete sweep. Same family
as everything else in this file. If you extend this scheme, the marker must be
the ONLY thing that can produce a match, so prose that discusses it never joins
the set.

**Two states, because a defect that gains a diagnostic CHANGES STATE rather than
leaving.** The underlying bug is unchanged and the ticket stays open; what
changes is the one property this sweep is about — whether a user can find out.
`__thread` made that move on the day of the sweep (`f64f2f088`, hours after it
was marked), and the transition is worth more than either state alone: it is the
shape every other member should be aiming for if it cannot be fixed before the
release.

**Re-tagging is a RULING, not bookkeeping.** frankA landed that warning, left
the old heading in place, and asked rather than demoting — correctly, because
the list is derived from these headings, so an edit silently changes the set. A
heading change should be made by whoever has to defend the list, after
re-measuring. That is how it happened here.

Cite that grep, never this file's table — a list transcribed into prose is stale
the first time somebody files or closes one, and this document has no way to
know. If the two disagree, the grep is right.

## Before you re-run this sweep: ASSERT THE FIXTURE, then believe the refusal

Banked because it nearly inverted a row of the table below, and it would have
inverted it in the SAFE-LOOKING direction.

Mid-sweep the scratchpad directory was removed under me. A `cat > $S/ld.c`
heredoc failed, and the very next command handed that path to the compiler:

```sh
./compiler/pascal26 $S/ld.c $S/ld_pxx || echo "  pxx: refused"
```

It printed `pxx: refused`. **That refusal was about the missing FILE and read
exactly like a result about `long double`** — and it would have entered the
table as "pxx refuses long double", which is the opposite of the truth and would
have moved that ticket OUT of the release-risk set. A refusal is the reassuring
answer here: a refusal is the class a beta may ship.

The guard is one line, and it must come before anything reads the compiler's
output:

```sh
[ -s "$S/ld.c" ] || { echo "FIXTURE MISSING — not reporting a result"; exit 1; }
```

Same family as everything else in this file: the instrument did not error, it
answered a different question. Assert that the subject EXISTS before comparing
what it produced.

## The set as of 2026-09-06, all re-measured here rather than read

**`RELEASE-RISK: DIAGNOSED` (1):**
`bug-c-__thread-is-accepted-and-silently-ignored-...` (p60) — every thread still
shares one copy and the object still has zero `.tbss`/`.tdata` against gcc's
one, but since `f64f2f088` the compiler warns once per compilation. Measured
here: 0 warnings with no thread storage class, 1 with one declaration, 1 with
two. The only member a user can discover.

**`RELEASE-RISK: SILENT-WRONG` (3):**

| ticket | prio | what is silently wrong |
| --- | --- | --- |
| `bug-c-long-double-is-8-bytes-in-pxx-and-16-in-gcc` | 35 | `sizeof(long double)` and `sizeof(struct { long double x; })` are 16 under gcc, 8 under pxx, same source, both silent. An aggregate carrying one disagrees about its own size across any real C boundary. |
| `feature-c-crtl-stdio-buffering-and-setvbuf` | 55 | `setvbuf` discards all four arguments and returns 0 — which C99 7.19.5.6 defines as SUCCESS. A caller that correctly checks the return is told its request was honoured when nothing happened. |
| `bug-c-crtl-utoa-digit-loop-is-unbounded` | 25 | **Conditional.** Needs a wrong `base` reaching `__crtl_utoa`, which no user program supplies directly; when it fires it corrupts the stack with no diagnostic. Listed because the ticket is parked as the amplifier for an unnamed defect, so its trigger is precisely what nobody has found. |

## WARN or REFUSE? — the test is whether a self-consistent program exists

frankA's reasoning for making `__thread` a warning rather than a refusal, and it
generalises across this table, so it is recorded rather than left in one ticket.

**Not the population count.** `__thread` appears ZERO times under `test/`,
`lib/` and `examples/`, so refusing would have been free in this tree — which is
exactly why an empty population is not the argument. Real C from outside the
tree is where the cost lands.

**The test is whether a program using the construct can be CORRECT today.** A
single-threaded program that merely mentions `__thread` is right as it stands —
one copy shared is one copy — so refusing would break working programs to
protect broken ones. Warn.

Applied to the rest of the table:

- **`long double`** has the same shape. A single-TU pxx program using it is
  self-consistent at 8 bytes; the wrongness appears only at a boundary with
  something that says 16. So the proportionate remedy is a warning naming the
  boundary, not a refusal. (Not implemented — noted so the next person does not
  reach for a refusal first.)
- **`setvbuf` does NOT.** Returning 0 is an active false statement, not a
  dropped hint: there is no program for which "I configured your buffering" is
  true. That one wants the return value corrected, and a warning would be the
  wrong instrument — it would leave the lie in place and add a note about it.

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
