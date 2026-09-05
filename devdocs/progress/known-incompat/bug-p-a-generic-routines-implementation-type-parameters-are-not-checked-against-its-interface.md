---
track: P
prio: 30
type: bug
blocked-by: []
status: known-incompat
owner: ""
created: 2026-09-05
summary: "KNOWN DIVERGENCE, not a defect — SETTLED 2026-09-05 by measurement, and the reason is not the one this ticket assumed. A unit may declare `generic procedure Test<T>` and implement `generic procedure Test<S>`; pxx accepts the differing impl-side spelling, which is the same deliberate rule pxx.skip already records for tgeneric20 and tgeneric30 — the implementation side of a generic routine need not echo the interface's type-parameter spelling. A RENAME cannot mislead, because both spellings denote the same single position. A SWAP could, and would make this `gap: accepts-invalid` instead — but it is UNREACHABLE: no two-parameter generic routine parses at all, and the control that proves it has neither a swap nor a rename (`generic procedure Pair<T, S>` identical in both sections still refuses with `expected '>' before ','`). Filed as bug-p-a-generic-routine-supports-exactly-one-type-parameter. tgenfunc17/18 are now skip-listed `wontfix: dialect-pass` WITH A TRIPWIRE: when the one-parameter limit is lifted the swap becomes reachable and this question re-opens."
---

# A generic routine's implementation type parameters are not checked

Measured 2026-09-05 at `abe92579b`, running `tools/run_pascal_conformance.sh`
as wired (`--strict-case --strict-operator`, driver-synthesis branch — these are
unit-shaped tests).

```pascal
unit tgenfunc17;
{$mode objfpc}{$H+}
interface
generic procedure Test<T>;      { declared with T }
implementation
generic procedure Test<S>;      { implemented with S — FPC rejects }
begin
end;
end.
```

| | tgenfunc17 / tgenfunc18 |
| --- | --- |
| fpc 3.2.2 | rejected (the suite marks both `{ %FAIL }`) |
| pxx at `abe92579b` | **ACCEPTED, exit 0, binary produced** |
| pxx at pin v403 | rejected — see below |

## The pin's rejection is NOT the check, and this is the part worth reading

The pinned compiler says:

```
error: unexpected token in a unit interface section: it starts no declaration
  near: unit tgenfunc17 ; interface >>> generic procedure Test
```

It never looked at the type parameters. **It refused the whole syntax**, and a
`%FAIL` row scores any refusal as a pass — so the row was green for a reason
that has nothing to do with what the test is about. `71deb21d4` (2026-09-04,
frankB, *"a `generic function` can be declared in a unit"*, closing
`bug-p-a-generic-function-cannot-be-declared-in-a-unit`) added the syntax, and
the row went red the moment the compiler became able to read the file. **So this
ticket is the residue of that one**, and whoever takes it should read frankB's
five-site note first — the declaration side is done and only the check is
missing.

Attribution established the way this repo says to: `%an` is `yoctobyte` on every
commit here and discriminates nothing, so it came from the `Claude-Session`
trailer (`session_019NLKYcGnZeZ3rWAJ6c8Yr2`) corroborated by the frankB
checkout's reflog carrying the `commit` entry for that sha. I had it wrong once
from `%an` before checking.

**So this is not a regression and reverting anything would be wrong.** It is a
capability gain that revealed a missing check, and the archive carries the
accidental pass: `devdocs/progress/tstate/conformance.tsv` records `pass` for
both rows as of 2026-09-02, measured by a compiler that could not parse them.

**That archive cannot be annotated and should not be.** It is regenerated
wholesale by Track T's `twatch.py` from the seven box (`tstate(seven): ... 550
conf`), so a note added by hand is overwritten at the next publish — and the tsv
is not wrong: it faithfully records what the harness said. The thing that turns
a refusal-for-the-wrong-reason into a `pass` is `%FAIL` semantics itself, which
scores ANY refusal as success and cannot distinguish "rejected for the stated
reason" from "rejected because the parser stopped three tokens earlier". THIS
TICKET is therefore the durable pointer: a future generics change that makes
these two rows move will find it by grepping the row names.

## Is it even a defect? Yes, and the rule says so specifically

CLAUDE.md: *"Us accepting what FPC rejects is not a defect"* — but also, for
inputs only a mistake produces, *"prefer the answer that leaves the mistake
visible."* An interface saying `<T>` and an implementation saying `<S>` is a
programmer error every time; accepting it silently is the answer that HIDES it.
So the wanted behaviour is a diagnostic, not FPC parity, and this is ranked as
a missing diagnostic rather than as a compat gap.

## Gate

`tools/run_pascal_conformance.sh` reaching **349 pass / 0 fail** (from 347/2),
with the count asserted rather than the exit code: **the harness SKIPs and exits
0 when `library_candidates/fpc-testsuite` is absent**, so a green there proves
nothing unless the suite is installed
(`tools/install_lib_candidates.sh fpc-testsuite`). Plus a positive control that
the matching case still compiles — `<T>` in both halves must not start failing.

## Reproduces at HEAD, and the scope question is the real one (frankS, 2026-09-05)

Confirmed at `0bbd82cd7` (sha `7fca108e4b85`): a unit declaring
`generic procedure Test<T>` and implementing `generic procedure Test<S>` is
accepted, and `specialize Test<Integer>(1)` from an importer runs.

**Not filed to `rejected/`, though it was on the way there.** The rule fits on
its face — *"us accepting what FPC rejects is not a defect"*, and a type
parameter renamed between interface and implementation is produced by a mistake
and nothing else, so the positional binding pxx uses gives that source the
meaning its author intended.

What stops the rejection is this ticket's own summary: **tgenfunc17.pp and
tgenfunc18.pp are two live FAILs in an otherwise 347/2 conformance run.**
`rejected/` is not ranked, so rejecting this leaves two rows red permanently
with nothing pointing at why — the next person to read that run files it again.

Two answers and this is a fork, not a judgement call, so it goes to U rather
than being settled here:

- **`known-incompat/`** — the divergence is TRUE, reproducible, and CHOSEN; the
  two conformance rows are then expected FAILs with a citation, not noise.
- **Implement the check** — cheap, and it costs nothing at runtime, on the view
  that a diagnostic which catches a certain mistake is worth having even where
  FPC-parity is not the reason.

The thing NOT to do is leave it at prio 30 in the ranker, where it is neither
chosen nor scheduled.

## 2026-09-05 (frankS) — there is a standing ruling on this exact family

frankD offered this row as a **rerating** candidate rather than a fix, on the
CLAUDE.md rule that us accepting what FPC rejects is not a defect. The
conformance suite has already decided the neighbouring cases, and the entries sit
two lines from where these would go in `test/pascal-conformance/pxx.skip`:

```
tgeneric20.pp  wontfix: dialect-pass — generic method impl without <T> marker —
               PXX's generics surface deliberately accepts the stripped form
               (3d71edcf); not a bug
tgeneric30.pp  wontfix: dialect-pass — mode-delphi generic method impl without
               <T> — PXX's Delphi-generics rewriter deliberately accepts the
               bare name (3d71edcf); not a bug
```

Both say the same thing: **the implementation side of a generic routine is not
required to echo the interface's type-parameter spelling.** `<T>` declared and
`<S>` implemented is that rule with a rename instead of an omission, so the
default disposition is `wontfix: dialect-pass` — which also makes the 347/2 run
read true, because a `dialect-pass` row is excluded from the adjusted pass rate
instead of sitting red forever.

**One measurement is owed before that is written down.** The suite's taxonomy has
a second bucket, `gap: accepts-invalid` (a real missing diagnostic), and the
discriminator is whether the acceptance can mislead rather than merely be lax.
Renaming one parameter cannot. **Swapping two can**: `generic procedure Test<T,S>`
declared against `generic procedure Test<S,T>` implemented reads as a deliberate
mapping and is positional, so a reader is told something false by their own
source. If pxx accepts THAT silently it is `accepts-invalid`, not `dialect-pass`,
and the fix is a diagnostic rather than a rerating.

Not yet measured: the pin cannot answer it (it refuses `generic procedure`
outright — the same accidental-%FAIL trap this ticket already documents), so it
needs a HEAD build. Do the swap probe first; the disposition follows from it.

## 2026-09-05 (frankS) — SETTLED: dialect-pass, and the reason is that the hazard cannot be reached

The measurement this ticket was waiting on is done, and it went the way frankD
predicted — but not for the reason either of us gave.

**The swap probe cannot be run, because no two-parameter generic routine parses
at all.** Measured at `e0e0fb2ae4ed`:

| construct | result |
| --- | --- |
| `generic procedure Solo<T>(a: T)` — one param, matching | **works**, prints `solo=5` |
| `generic TPair<T, S> = class` — two params, CLASS | **parses and builds** |
| `generic procedure Pair<T, S>` — two params, ROUTINE, *identical* in both sections | **`expected '>' before ','`** |

The third row is the control that matters: it has **no swap and no rename**, and
it still refuses. So the earlier reading — that pxx "accepts" the swap — was
never tested; the construct does not exist. Filed as
[[bug-p-a-generic-routine-supports-exactly-one-type-parameter]]:
`GenericFuncs[].Param` is a single `AnsiString`, so the data model holds exactly
one type parameter for a routine.

**Therefore the disposition is `wontfix: dialect-pass`, matching tgeneric20 and
tgeneric30**, and it is now safe rather than merely precedented:

- A **rename** (`<T>` declared, `<S>` implemented) is all that can occur, and a
  rename cannot mislead — both spellings denote the same single position. That
  is exactly the "implementation side need not echo the interface's
  type-parameter spelling" rule the two existing entries already record.
- A **swap** could mislead, and is the case that would have made this
  `gap: accepts-invalid` instead. It is unreachable.

**The trap here was real and worth naming.** frankB's warning was that a known
gap described one severity class too low is harder to find than an unknown one,
*because the existing note answers the question you were about to ask*. Inheriting
tgeneric20/30's bucket without measuring would have been exactly that. The bucket
turns out to be right — but it is right because of a parse limitation nobody had
connected to it, not because the family argument covers the swap. Those are
different reasons and only one of them survives the parse gap being fixed.

**So the skip entries carry a tripwire**, and this is the part that must not be
dropped: when
[[bug-p-a-generic-routine-supports-exactly-one-type-parameter]]
lands, the swap becomes reachable and this question re-opens. The note in
`pxx.skip` says so, so the next reader inherits the caveat and not just the
verdict.
