---
slug: bug-r-a-duplicate-forward-in-rparser-breaks-the-fpc-seed-build
track: R
prio: 85
type: bug
status: backlog
blocked-by: []
summary: "compiler/rparser.inc declares `function RParseAggregateIntoNode(targetNode, ci: Integer): Integer; forward;` TWICE — :1498 (from e3043236b) and :2754 (from fcfe1cba1). FPC rejects the second: `Error: Function is already declared Public/Forward`, and the whole compile aborts. This breaks the FPC-SEED BOOTSTRAP for every lane, not just Track R: `tools/gate.sh quick` goes RED at the 'FPC seed canary' step on plain origin/master. pxx itself tolerates the duplicate, so self-host is green and nothing else complains — the seed is the only thing that notices."
owner: unassigned
---

# A duplicate forward in `rparser.inc` breaks the FPC seed build

Found 2026-08-29 by frankA, gating an unrelated Track A fix. **Not fixed here:
`rparser.inc` is Track R's file and another agent may be mid-edit in it.**

## Symptom

```
rparser.inc(2754,10) Error: Function is already declared Public/Forward
  "RParseAggregateIntoNode(LongInt;LongInt):LongInt;"
compiler.pas(2133) Fatal: There were 1 errors compiling module, stopping
Error: /usr/bin/ppcx64 returned an error exitcode
gate: RED
```

## Cause

Two identical forward declarations survive in the same file:

| line | added by |
| --- | --- |
| 1498 | `e3043236b` feat(rust): enum values in expression position, and derived clone |
| 2754 | `fcfe1cba1` feat(rust): the engine's own idioms compile — chess.rs shapes end to end |

The definition is at :2825. FPC allows one forward per routine; a second is an
error even when identical. Deleting **either** forward should do it — keep the
one that actually precedes the earliest call (`:1506`), which is :1498, and drop
:2754.

## Why it matters more than it looks

**pxx does not care.** It accepts the duplicate, so `make compiler/pascal26`
converges, the self-host fixedpoint is green, and `testmgr --tier quick` passes.
The ONLY thing that notices is FPC — which is the seed. So the tree is in the
state where everything an agent normally checks says fine, and the ability to
**bootstrap the compiler from source** is gone. That is the one property the
seed canary exists to protect.

It has been on `origin/master` since the two commits merged, and it fails on a
clean checkout with no local changes.

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
