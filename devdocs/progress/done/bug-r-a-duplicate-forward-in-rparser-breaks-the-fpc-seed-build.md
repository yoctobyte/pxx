---
slug: bug-r-a-duplicate-forward-in-rparser-breaks-the-fpc-seed-build
track: R
prio: 85
type: bug
status: done
blocked-by: []
summary: "compiler/rparser.inc declares `function RParseAggregateIntoNode(targetNode, ci: Integer): Integer; forward;` TWICE — :1498 (from e3043236b) and :2786 (from fcfe1cba1). FPC rejects the second: `Error: Function is already declared Public/Forward`, and the whole compile aborts. This breaks the FPC-SEED BOOTSTRAP for every lane, not just Track R. It does NOT show up as a gate failure for a clean tree — the canary's arming rule skips it once the break is on origin/master; it fires on the next person to touch compiler/ and names R's file (split out as bug-a-the-fpc-seed-canary-skips-a-break-already-on-master). pxx itself tolerates the duplicate, so self-host is green and nothing else complains — the seed is the only thing that notices."
owner: unassigned
---

# A duplicate forward in `rparser.inc` breaks the FPC seed build

Found 2026-08-29 by frankA, gating an unrelated Track A fix. **Not fixed here:
`rparser.inc` is Track R's file and another agent may be mid-edit in it.**

## Symptom

```
rparser.inc(2786,10) Error: Function is already declared Public/Forward
  "RParseAggregateIntoNode(LongInt;LongInt):LongInt;"
compiler.pas(2133) Fatal: There were 1 errors compiling module, stopping
Error: /usr/bin/ppcx64 returned an error exitcode
gate: RED
```

## Cause

Two identical forward declarations survive in the same file:

| line | added by |
| --- | --- |
| 1498 | `e3043236b` (20:26) feat(rust): enum values in expression position, and derived clone |
| 2786 | `fcfe1cba1` (18:28) feat(rust): the engine's own idioms compile — chess.rs shapes end to end |

The definition is at :2882. FPC allows one forward per routine; a second is an
error even when identical. Deleting **either** forward should do it — keep the
one that actually precedes the earliest call (`:1506`), which is :1498, and drop
:2786.

## Why it matters more than it looks

**pxx does not care.** It accepts the duplicate, so `make compiler/pascal26`
converges, the self-host fixedpoint is green, and `testmgr --tier quick` passes.
The ONLY thing that notices is FPC — which is the seed. So the tree is in the
state where everything an agent normally checks says fine, and the ability to
**bootstrap the compiler from source** is gone. That is the one property the
seed canary exists to protect.

It has been on `origin/master` since the two commits merged, and it fails on a
clean checkout with no local changes.

## Measured at HEAD `fa238413e`, 2026-08-29

```
$ fpc -Mobjfpc -O2 -Tlinux -Px86_64 -FU$D -FE$D -o$D/seed26 compiler/compiler.pas
rparser.inc(2786,10) Error: Function is already declared Public/Forward
compiler.pas(2133) Fatal: There were 1 errors compiling module, stopping
fpc exit=1
```

## The worse half: the canary that exists to catch this now SKIPS it

This is the part to fix first, and it is Track A/T's, not R's.

`gate.sh quick` arms the seed canary only when
`git diff merge-base(origin/master, HEAD) -- compiler/` is **non-empty** — a
deliberate choice, documented at `tools/gate.sh:262-273`, so the gate does not
re-run a sibling's already-pushed compiler commit on every invocation. The
consequence was not considered:

- **Once a seed break is ON origin/master, it is invisible.** A worker with no
  local `compiler/` changes has an empty diff, so the canary SKIPs. It cannot
  report a failure it never runs. Two gates on this box printed `PASS` on
  2026-08-29 while the seed was already broken upstream — one at 20:34, eight
  minutes after `e3043236b` landed the duplicate, because that tree had not yet
  pulled it.
- **And the next person to touch `compiler/` gets blamed.** Their change arms
  the canary, the canary fails, and the failure names `rparser.inc` — someone
  else's file, someone else's commit. I spent a gate run and a bisect-shaped
  hour on exactly that before measuring.

So the arming rule converts a repo-wide breakage into a silent one that
mis-attributes on its next sighting. The rule is right about not re-running
siblings' work; it is wrong to treat "already on origin" as "already proven".
Cheapest correction: keep the arming rule, but ALSO arm when the previous
canary result for the current `origin/master` sha is unknown or RED — i.e.
remember the last seed-green sha, and skip only when `origin/master` has not
moved past it. That preserves the cost argument (one seed build per
origin/master advance, concurrent, ~11s) and closes the hole.

## A gap this exposes in the fast check — for whoever owns `forwardlint`

`tools/gate.sh quick` runs **two** FPC-related steps, and the fast one was
silent:

```
PASS  fpc seed compiles (forward decls)   (3s)     <- tools/forwardlint.py
FAIL  FPC seed canary (concurrent)                 <- the real ppcx64 build
```

`forwardlint` exists precisely so seed drift is caught in ~4s instead of
minutes. It enumerates routines called from an include EARLIER than the one
defining them — i.e. **MISSING** forwards. A **DUPLICATE** forward is the same
class of defect (a forward-declaration mistake that only FPC rejects) and it
does not look for it. Adding "the same routine forwarded twice in one file" is
a few lines and would move this from a minutes-long failure to a seconds-long
one. Track T or A, whoever holds `tools/forwardlint.py`.

## Gate

`tools/gate.sh quick` green — specifically the `FPC seed canary` step — plus
Rust tests still passing and the self-host fixedpoint unchanged.

## Log
- 2026-08-29 — resolved, commit PENDING-COMMIT.
