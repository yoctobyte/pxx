---
track: T
prio: 30
type: bug
blocked-by: []
summary: "One gate.sh quick run reported the FPC seed canary RED with 'symtab.inc(5934,30) Identifier not found ByRefArgNeedsLvalue' — but line 5934 of that file contains an unrelated loop, and the real call sites are at 6185/6186, AFTER the definition at 6099. Not reproducible: fpc compiled the identical tree rc=0 twice by hand and the next gate.sh run was GREEN. Evidence points at the canary reading a stale/other tree state, the same class the fixedpoint step already defends against; a false RED costs an agent a full investigation."
---

# An FPC-seed-canary RED cited line numbers that cannot contain the identifier

- **Type:** bug (false RED, not reproduced) — **Track T** (`tools/gate.sh` is
  T's; filed by Track A, not fixed here)
- **Status:** backlog
- **Opened:** 2026-08-21

## What happened

`tools/gate.sh quick`, log dir `/tmp/pxx-gate-3976445`:

```
  FAIL  FPC seed canary (concurrent)  /tmp/pxx-gate-3976445/fpc-seed.log
        symtab.inc(5934,30) Error: Identifier not found "ByRefArgNeedsLvalue"
        symtab.inc(5935,6) Error: Identifier not found "ByRefArgNeedsLvalue"
```

The working tree at that moment (and now) says otherwise:

- `compiler/symtab.inc:5934` is inside `RegisterProc`'s parameter-compare loop
  and contains no such identifier;
- `ByRefArgNeedsLvalue` is DEFINED at `symtab.inc:6099` and used at `6185`/`6186`
  — after its definition, which is why FPC is happy with it;
- the tree was clean apart from my own edits, none of them in `symtab.inc`
  (`git status` checked at the time).

Immediately after, on the identical tree:

- `fpc -Mobjfpc -O2 -Tlinux -Px86_64 ... compiler/compiler.pas` by hand: **rc=0**;
- the next `tools/gate.sh quick`: **GREEN**, canary included.

So the canary compiled something that was not the tree it named — the file it
read had that call roughly 165 lines earlier than the current file does.

## Why it is worth a ticket even though it did not reproduce

The canary's failure text tells the reader to add a forward declaration. Acting
on that would have meant editing a file that was already correct. What it cost
in practice was an investigation: grep, `git log`, a hand FPC compile, and a
second gate run, before the RED could be dismissed — on a night where the same
box had already produced a false DOWN
([[bug-t-twatch-status-says-down-while-the-daemon-is-alive-and-testing]]).

The failure class is one this tooling already knows about.
`tools/selfhost_fixedpoint.sh` carries a comment about exactly it: *"any
concurrent `make` in the same clone replaces it mid-check — observed on plexus
with 17 other build processes on the box, reported as a self-host FAIL when
nothing was wrong"*, and it fixed that by snapshotting the artefact and
hash-verifying the copy. The canary reads the SOURCE tree, concurrently with
the fixedpoint build and `testmgr --tier quick`, with no such protection.

## Suggested shape (T's call)

- On a canary FAIL, re-run it once serially before reporting RED. A real
  forward-declaration drift is deterministic and survives the re-run; a
  stale-read does not. The cost is paid only on failure.
- Or make the canary compile from a snapshot of `compiler/` taken at one
  instant, mirroring what `selfhost_fixedpoint.sh` does for the binary.
- Either way, when the reported error's line does not contain the reported
  identifier, say so rather than printing the "add a forward" advice, which is
  wrong exactly when this happens.

## What is NOT claimed

No root cause. Nothing else on the box wrote `compiler/symtab.inc` (the Track T
watcher runs in `/home/neo/trackt-watch`, its own clone, verified by
`/proc/<pid>/cwd`), and I could not construct a repro. This ticket is the
EVIDENCE, deliberately not a theory — recording a plausible mechanism as the
cause is how this repo has bought wrong root causes before.
